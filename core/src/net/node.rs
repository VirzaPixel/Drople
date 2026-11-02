use std::collections::{BTreeMap, HashMap};
use std::fs::{File, OpenOptions};
use std::io::{Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use base64::Engine;
use base64::engine::general_purpose::STANDARD as B64;
use futures::StreamExt;
use libp2p::identity::Keypair;
use libp2p::multiaddr::Protocol;
use libp2p::request_response::{self, Message as ReqResMessage, ProtocolSupport};
use libp2p::swarm::{NetworkBehaviour, SwarmEvent};
use libp2p::{
    Multiaddr, PeerId, StreamProtocol, Swarm, SwarmBuilder, dcutr, identify, mdns, noise, ping,
    relay, tcp, yamux,
};
use rusqlite::Connection;
use serde::Serialize;
use sha2::{Digest, Sha256};

use crate::db;
use crate::error::{DropleError, Result};
use crate::file::chunking;
use crate::net::identity;
use crate::net::pairing;
use crate::net::wire::WireMessage;
use crate::sync;

pub const WIRE_PROTOCOL: &str = "/drople/wire/1";
pub const RECEIVE_DIR_SETTING: &str = "file_receive_dir";

#[derive(Debug, Clone, Default, Serialize)]
pub struct PeerEntry {
    pub id: String,
    pub name: String,
    pub last_seen: i64,
    pub connected: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub latency_ms: Option<u64>,
    pub addresses: Vec<String>,
    #[serde(default)]
    pub fingerprint: String,
    #[serde(default)]
    pub code: String,
    #[serde(default)]
    pub platform: String,
}

#[derive(Debug, Clone, Default)]
pub struct SharedState {
    pub local_peer_id: String,
    pub local_fingerprint: String,
    pub local_code: String,
    pub listen_addrs: Vec<String>,
    pub peers: BTreeMap<String, PeerEntry>,
    pub pending_approvals: BTreeMap<String, String>,
    pub rejected_peers: std::collections::HashSet<String>,
    pub pairing_notifications: Vec<(String, bool)>,
}

#[derive(Debug)]
enum NetworkCommand {
    DialPeer {
        peer_id: String,
        addrs: Vec<String>,
    },
    DialAddr(String),
    AddRelay(String),
    SyncPeer {
        peer_id: String,
    },
    SendFile {
        peer_id: String,
        transfer_id: String,
        file_path: String,
    },
    RequestPairing {
        peer_id: String,
        addrs: Vec<String>,
    },
    DisconnectPeer(String),
    ApprovePeer(String),
    RejectPeer(String),
    Shutdown,
}

#[derive(NetworkBehaviour)]
#[behaviour(prelude = "libp2p::swarm::derive_prelude")]
struct DropleBehaviour {
    relay: relay::client::Behaviour,
    dcutr: dcutr::Behaviour,
    mdns: mdns::tokio::Behaviour,
    identify: identify::Behaviour,
    ping: ping::Behaviour,
    wire:
        request_response::Behaviour<request_response::json::codec::Codec<WireMessage, WireMessage>>,
}

struct OutboundTransfer {
    peer: PeerId,
    file_name: String,
    file_size: i64,
    file_hash: String,
    chunks: Vec<chunking::FileChunk>,
    next_index: usize,
    offer_acked: bool,
}

struct IncomingTransfer {
    file: File,
    hasher: Sha256,
    expected_hash: String,
    written: i64,
    received: std::collections::HashSet<u32>,
}

#[derive(Clone, Copy, PartialEq)]
enum PendingKind {
    Offer,
    Chunk,
    Done,
}

struct PendingAction {
    transfer_id: String,
    kind: PendingKind,
}

#[derive(Default)]
struct WireState {
    outbound: HashMap<String, OutboundTransfer>,
    pending: HashMap<request_response::OutboundRequestId, PendingAction>,
    incoming: HashMap<String, IncomingTransfer>,
    pairing_outbound: std::collections::HashSet<PeerId>,
    pairing_requests: HashMap<request_response::OutboundRequestId, PeerId>,
    pairing_inbound: HashMap<String, request_response::ResponseChannel<WireMessage>>,
    manually_disconnected: std::collections::HashSet<PeerId>,
}

pub struct NodeHandle {
    local_peer_id: String,
    cmd_tx: async_channel::Sender<NetworkCommand>,
    shared: Arc<Mutex<SharedState>>,
}

impl NodeHandle {
    pub fn local_peer_id(&self) -> &str {
        &self.local_peer_id
    }

    pub fn snapshot(&self) -> SharedState {
        self.shared.lock().map(|s| s.clone()).unwrap_or_default()
    }

    pub fn take_pairing_notifications(&self) -> Vec<(String, bool)> {
        self.shared
            .lock()
            .map(|mut state| std::mem::take(&mut state.pairing_notifications))
            .unwrap_or_default()
    }

    pub fn wait_listen_addr(&self, timeout: Duration) {
        let started = std::time::Instant::now();
        while started.elapsed() < timeout {
            if !self.snapshot().listen_addrs.is_empty() {
                return;
            }
            std::thread::sleep(Duration::from_millis(20));
        }
    }

    pub fn dial_peer(&self, peer_id: &str, addrs: &[String]) {
        let _ = self.cmd_tx.send_blocking(NetworkCommand::DialPeer {
            peer_id: peer_id.to_string(),
            addrs: addrs.to_vec(),
        });
    }

    pub fn dial_addr(&self, addr: &str) {
        let _ = self
            .cmd_tx
            .send_blocking(NetworkCommand::DialAddr(addr.to_string()));
    }

    pub fn add_relay(&self, addr: &str) {
        let _ = self
            .cmd_tx
            .send_blocking(NetworkCommand::AddRelay(addr.to_string()));
    }

    pub fn request_sync(&self, peer_id: &str) {
        let _ = self.cmd_tx.send_blocking(NetworkCommand::SyncPeer {
            peer_id: peer_id.to_string(),
        });
    }

    pub fn send_file(&self, peer_id: &str, transfer_id: &str, file_path: &str) {
        let _ = self.cmd_tx.send_blocking(NetworkCommand::SendFile {
            peer_id: peer_id.to_string(),
            transfer_id: transfer_id.to_string(),
            file_path: file_path.to_string(),
        });
    }

    pub fn approve_peer(&self, peer_id: &str) {
        let _ = self
            .cmd_tx
            .send_blocking(NetworkCommand::ApprovePeer(peer_id.to_string()));
    }

    pub fn request_pairing(&self, peer_id: &str, addrs: &[String]) {
        let _ = self.cmd_tx.send_blocking(NetworkCommand::RequestPairing {
            peer_id: peer_id.to_string(),
            addrs: addrs.to_vec(),
        });
    }

    pub fn disconnect_peer(&self, peer_id: &str) {
        let _ = self
            .cmd_tx
            .send_blocking(NetworkCommand::DisconnectPeer(peer_id.to_string()));
    }

    pub fn reject_peer(&self, peer_id: &str) {
        let _ = self
            .cmd_tx
            .send_blocking(NetworkCommand::RejectPeer(peer_id.to_string()));
    }

    pub fn stop(self) {
        let _ = self.cmd_tx.send_blocking(NetworkCommand::Shutdown);
    }
}

pub fn spawn(keypair: Keypair, db_path: Option<String>, device_name: String) -> Result<NodeHandle> {
    let local_peer_id = keypair.public().to_peer_id().to_string();
    let local_fingerprint = identity::fingerprint_for(&keypair);
    let local_code = pairing::short_code(&local_peer_id);
    let (cmd_tx, cmd_rx) = async_channel::unbounded();
    let shared = Arc::new(Mutex::new(SharedState {
        local_peer_id: local_peer_id.clone(),
        local_fingerprint,
        local_code,
        ..Default::default()
    }));

    let (ready_tx, ready_rx) = std::sync::mpsc::channel::<Result<()>>();
    let shared_thread = Arc::clone(&shared);

    std::thread::Builder::new()
        .name("drople-p2p".into())
        .spawn(move || {
            let runtime = tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build();
            match runtime {
                Ok(rt) => {
                    rt.block_on(run(
                        keypair,
                        device_name,
                        cmd_rx,
                        shared_thread,
                        db_path,
                        ready_tx,
                    ));
                }
                Err(e) => {
                    let _ = ready_tx.send(Err(DropleError::Network(e.to_string())));
                }
            }
        })
        .map_err(|e| DropleError::Network(format!("gagal spawn thread P2P: {e}")))?;

    match ready_rx.recv() {
        Ok(Ok(())) => Ok(NodeHandle {
            local_peer_id,
            cmd_tx,
            shared,
        }),
        Ok(Err(e)) => Err(e),
        Err(_) => Err(DropleError::Network(
            "thread P2P berhenti saat start".into(),
        )),
    }
}

async fn run(
    keypair: Keypair,
    device_name: String,
    cmd_rx: async_channel::Receiver<NetworkCommand>,
    shared: Arc<Mutex<SharedState>>,
    db_path: Option<String>,
    ready_tx: std::sync::mpsc::Sender<Result<()>>,
) {
    let mut swarm = match build_swarm(keypair, device_name) {
        Ok(swarm) => swarm,
        Err(e) => {
            let _ = ready_tx.send(Err(e));
            return;
        }
    };

    if let Err(e) = swarm.listen_on("/ip4/0.0.0.0/tcp/0".parse::<Multiaddr>().unwrap()) {
        let _ = ready_tx.send(Err(DropleError::Network(format!("listen tcp: {e}"))));
        return;
    }
    let _ = swarm.listen_on("/ip4/0.0.0.0/udp/0/quic-v1".parse::<Multiaddr>().unwrap());

    let mut relay_addr: Option<Multiaddr> = std::env::var("DROPLE_RELAY_ADDR")
        .ok()
        .and_then(|v| v.trim().parse::<Multiaddr>().ok());
    if let Some(addr) = relay_addr.clone() {
        let _ = swarm.dial(addr);
    }

    let db_conn: Option<Connection> = db_path
        .as_deref()
        .filter(|p| *p != ":memory:")
        .and_then(|p| Connection::open(p).ok());

    let mut wire = WireState::default();
    let _ = ready_tx.send(Ok(()));

    loop {
        tokio::select! {
            event = swarm.select_next_some() => {
                handle_swarm_event(
                    event,
                    &shared,
                    &db_conn,
                    &mut relay_addr,
                    &mut swarm,
                    &mut wire,
                );
            }
            command = cmd_rx.recv() => {
                match command {
                    Ok(NetworkCommand::DialPeer { peer_id, addrs }) => {
                        if let Ok(peer) = peer_id.parse::<PeerId>() {
                            wire.manually_disconnected.remove(&peer);
                        }
                        dial_peer(&mut swarm, &peer_id, &addrs, relay_addr.as_ref());
                    }
                    Ok(NetworkCommand::DialAddr(addr)) => {
                        if let Ok(addr) = addr.parse::<Multiaddr>() {
                            let _ = swarm.dial(addr);
                        }
                    }
                    Ok(NetworkCommand::AddRelay(addr)) => {
                        if let Ok(addr) = addr.parse::<Multiaddr>() {
                            let _ = swarm.dial(addr.clone());
                            relay_addr = Some(addr);
                        }
                    }
                    Ok(NetworkCommand::SyncPeer { peer_id }) => {
                        start_sync(&mut swarm, &peer_id);
                    }
                    Ok(NetworkCommand::SendFile { peer_id, transfer_id, file_path }) => {
                        start_outbound_file(
                            &mut swarm,
                            &mut wire,
                            &db_conn,
                            &peer_id,
                            &transfer_id,
                            &file_path,
                        );
                    }
                    Ok(NetworkCommand::RequestPairing { peer_id, addrs }) => {
                        if let Ok(peer) = peer_id.parse::<PeerId>() {
                            wire.manually_disconnected.remove(&peer);
                            if let Ok(mut state) = shared.lock() {
                                state.rejected_peers.remove(&peer_id);
                            }
                            if swarm.is_connected(&peer) {
                                send_pairing_request(&mut swarm, &mut wire, peer);
                            } else {
                                wire.pairing_outbound.insert(peer);
                                dial_peer(&mut swarm, &peer_id, &addrs, relay_addr.as_ref());
                            }
                        }
                    }
                    Ok(NetworkCommand::DisconnectPeer(peer_id)) => {
                        if let Ok(peer) = peer_id.parse::<PeerId>() {
                            wire.manually_disconnected.insert(peer);
                            let _ = swarm.disconnect_peer_id(peer);
                            set_connected(&shared, &db_conn, &peer, false);
                        }
                    }
                    Ok(NetworkCommand::ApprovePeer(peer_id)) => {
                        if let Ok(mut state) = shared.lock() {
                            state.pending_approvals.remove(&peer_id);
                            state.rejected_peers.remove(&peer_id);
                        }
                        if let Some(channel) = wire.pairing_inbound.remove(&peer_id) {
                            let _ = swarm.behaviour_mut().wire.send_response(
                                channel,
                                WireMessage::PairingResult { accepted: true },
                            );
                        }
                    }
                    Ok(NetworkCommand::RejectPeer(peer_id)) => {
                        if let Ok(mut state) = shared.lock() {
                            state.pending_approvals.remove(&peer_id);
                            state.rejected_peers.insert(peer_id.clone());
                        }
                        if let Some(channel) = wire.pairing_inbound.remove(&peer_id) {
                            let _ = swarm.behaviour_mut().wire.send_response(
                                channel,
                                WireMessage::PairingResult { accepted: false },
                            );
                        }
                    }
                    Ok(NetworkCommand::Shutdown) | Err(_) => break,
                }
            }
        }
    }
}

fn build_swarm(keypair: Keypair, device_name: String) -> Result<Swarm<DropleBehaviour>> {
    let local_peer_id = keypair.public().to_peer_id();
    let codec = request_response::json::codec::Codec::<WireMessage, WireMessage>::default()
        .set_request_size_maximum(4 * 1024 * 1024)
        .set_response_size_maximum(32 * 1024 * 1024);
    let rr_config =
        request_response::Config::default().with_request_timeout(Duration::from_secs(120));

    let swarm = SwarmBuilder::with_existing_identity(keypair)
        .with_tokio()
        .with_tcp(
            tcp::Config::default(),
            noise::Config::new,
            yamux::Config::default,
        )
        .map_err(net_err)?
        .with_quic()
        .with_relay_client(noise::Config::new, yamux::Config::default)
        .map_err(net_err)?
        .with_behaviour(|key, relay_client| {
            Ok::<_, Box<dyn std::error::Error + Send + Sync>>(DropleBehaviour {
                relay: relay_client,
                dcutr: dcutr::Behaviour::new(local_peer_id),
                mdns: mdns::tokio::Behaviour::new(
                    mdns::Config::default(),
                    key.public().to_peer_id(),
                )?,
                identify: identify::Behaviour::new(
                    identify::Config::new("/drople/1.0.0".into(), key.public()).with_agent_version(
                        format!("Drople|{}|{device_name}", std::env::consts::OS),
                    ),
                ),
                ping: ping::Behaviour::default(),
                wire: request_response::Behaviour::with_codec(
                    codec,
                    [(StreamProtocol::new(WIRE_PROTOCOL), ProtocolSupport::Full)],
                    rr_config,
                ),
            })
        })
        .map_err(net_err)?
        .with_swarm_config(|cfg| cfg.with_idle_connection_timeout(Duration::from_secs(120)))
        .build();
    Ok(swarm)
}

fn net_err(e: impl std::fmt::Display) -> DropleError {
    DropleError::Network(e.to_string())
}

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn ns_to_ms(ns: u64) -> u64 {
    ns / 1_000_000
}

fn upsert_peer(
    shared: &Arc<Mutex<SharedState>>,
    db_conn: &Option<Connection>,
    peer_id: &PeerId,
    name: Option<&str>,
    addrs: &[Multiaddr],
    connected: Option<bool>,
    fingerprint: Option<&str>,
    platform: Option<&str>,
) {
    let id = peer_id.to_string();
    let addr_strings: Vec<String> = addrs.iter().map(|a| a.to_string()).collect();

    if let Ok(mut state) = shared.lock() {
        let entry = state.peers.entry(id.clone()).or_insert_with(|| PeerEntry {
            id: id.clone(),
            name: String::new(),
            last_seen: 0,
            connected: false,
            latency_ms: None,
            addresses: Vec::new(),
            fingerprint: String::new(),
            code: pairing::short_code(&id),
            platform: String::new(),
        });
        if let Some(n) = name {
            entry.name = n.to_string();
        }
        if !addr_strings.is_empty() {
            entry.addresses = addr_strings.clone();
        }
        if let Some(c) = connected {
            entry.connected = c;
        }
        if let Some(f) = fingerprint {
            entry.fingerprint = f.to_string();
        }
        if let Some(p) = platform {
            entry.platform = p.to_string();
        }
        entry.last_seen = now_millis();
    }

    if let Some(conn) = db_conn {
        let _ = db::upsert_peer(
            conn,
            &id,
            name.unwrap_or(""),
            &id,
            fingerprint.unwrap_or(""),
        );
    }
}

fn set_connected(
    shared: &Arc<Mutex<SharedState>>,
    db_conn: &Option<Connection>,
    peer_id: &PeerId,
    connected: bool,
) {
    if let Ok(mut state) = shared.lock() {
        if let Some(entry) = state.peers.get_mut(&peer_id.to_string()) {
            entry.connected = connected;
            entry.last_seen = now_millis();
        }
    }
    if let Some(conn) = db_conn {
        let id = peer_id.to_string();
        let _ = db::upsert_peer(conn, &id, "", &id, "");
    }
}

fn handle_swarm_event(
    event: SwarmEvent<DropleBehaviourEvent>,
    shared: &Arc<Mutex<SharedState>>,
    db_conn: &Option<Connection>,
    relay_addr: &mut Option<Multiaddr>,
    swarm: &mut Swarm<DropleBehaviour>,
    wire: &mut WireState,
) {
    match event {
        SwarmEvent::NewListenAddr { address, .. } => {
            if let Ok(mut state) = shared.lock() {
                let addr = address.to_string();
                if !state.listen_addrs.contains(&addr) {
                    state.listen_addrs.push(addr);
                }
            }
        }
        SwarmEvent::ConnectionEstablished { peer_id, .. } => {
            set_connected(shared, db_conn, &peer_id, true);
            upsert_peer(shared, db_conn, &peer_id, None, &[], Some(true), None, None);
            if wire.pairing_outbound.remove(&peer_id) {
                send_pairing_request(swarm, wire, peer_id);
            }
            resume_peer_transfers(swarm, wire, db_conn, &peer_id);
        }
        SwarmEvent::ConnectionClosed {
            peer_id,
            num_established,
            ..
        } => {
            if num_established == 0 {
                set_connected(shared, db_conn, &peer_id, false);
            }
        }
        SwarmEvent::OutgoingConnectionError { peer_id, error, .. } => {
            if let Some(peer_id) = peer_id {
                if !swarm.is_connected(&peer_id) {
                    set_connected(shared, db_conn, &peer_id, false);
                }
            }
            let _ = error;
        }
        SwarmEvent::Behaviour(DropleBehaviourEvent::Mdns(event)) => match event {
            mdns::Event::Discovered(list) => {
                for (peer_id, addr) in list {
                    if peer_id == *swarm.local_peer_id() {
                        continue;
                    }
                    upsert_peer(
                        shared,
                        db_conn,
                        &peer_id,
                        None,
                        &[addr.clone()],
                        None,
                        None,
                        None,
                    );
                    if wire.manually_disconnected.contains(&peer_id) {
                        continue;
                    }
                    let _ = swarm.dial(addr);
                }
            }
            mdns::Event::Expired(list) => {
                for (peer_id, _) in list {
                    if !swarm.is_connected(&peer_id) {
                        set_connected(shared, db_conn, &peer_id, false);
                    }
                }
            }
        },
        SwarmEvent::Behaviour(DropleBehaviourEvent::Identify(event)) => {
            if let identify::Event::Received { peer_id, info, .. } = event {
                let raw = info.agent_version;
                let (platform, name) = match raw.strip_prefix("Drople|") {
                    Some(rest) => match rest.split_once('|') {
                        Some((platform, name)) => (Some(platform.to_string()), name.to_string()),
                        None => (None, rest.to_string()),
                    },
                    None => {
                        let name = if raw.contains("libp2p") || raw.contains("rust-") {
                            format!(
                                "Perangkat {}",
                                &peer_id.to_string()[..6.min(peer_id.to_string().len())]
                            )
                        } else {
                            raw.clone()
                        };
                        (None, name)
                    }
                };
                upsert_peer(
                    shared,
                    db_conn,
                    &peer_id,
                    Some(&name),
                    &info.listen_addrs,
                    None,
                    None,
                    platform.as_deref(),
                );
            }
        }
        SwarmEvent::Behaviour(DropleBehaviourEvent::Ping(event)) => {
            if let Ok(rtt) = event.result {
                if let Ok(mut state) = shared.lock() {
                    if let Some(entry) = state.peers.get_mut(&event.peer.to_string()) {
                        entry.latency_ms = Some(ns_to_ms(rtt.as_nanos() as u64));
                    }
                }
            }
        }
        SwarmEvent::Behaviour(DropleBehaviourEvent::Relay(event)) => {
            if let relay::client::Event::ReservationReqAccepted { relay_peer_id, .. } = event {
                let circuit: Multiaddr = format!("/p2p/{relay_peer_id}/p2p-circuit")
                    .parse()
                    .expect("valid circuit multiaddr");
                let _ = swarm.listen_on(circuit);
            }
        }
        SwarmEvent::Behaviour(DropleBehaviourEvent::Wire(event)) => {
            handle_wire_event(event, shared, db_conn, swarm, wire);
        }
        SwarmEvent::Behaviour(DropleBehaviourEvent::Dcutr(_)) => {}
        _ => {}
    }
    let _ = relay_addr;
}

fn start_sync(swarm: &mut Swarm<DropleBehaviour>, peer_id: &str) {
    let Ok(peer) = peer_id.parse::<PeerId>() else {
        return;
    };
    let deltas = sync::local_deltas().unwrap_or_default();
    let _ = swarm
        .behaviour_mut()
        .wire
        .send_request(&peer, WireMessage::Sync { deltas });
}

fn start_outbound_file(
    swarm: &mut Swarm<DropleBehaviour>,
    wire: &mut WireState,
    db_conn: &Option<Connection>,
    peer_id: &str,
    transfer_id: &str,
    file_path: &str,
) {
    let Ok(peer) = peer_id.parse::<PeerId>() else {
        mark_transfer_failed(db_conn, transfer_id);
        return;
    };
    let path = Path::new(file_path);
    let chunks = match chunking::read_file_chunks(path, transfer_id) {
        Ok(chunks) => chunks,
        Err(e) => {
            let _ = e;
            mark_transfer_failed(db_conn, transfer_id);
            return;
        }
    };
    let file_name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("file")
        .to_string();

    let total = chunks.iter().map(|c| c.size() as i64).sum::<i64>();
    let file_hash = chunking::file_hash(path).unwrap_or_default();
    let transfer = OutboundTransfer {
        peer,
        file_name,
        file_size: total,
        file_hash,
        chunks,
        next_index: 0,
        offer_acked: false,
    };
    wire.outbound.insert(transfer_id.to_string(), transfer);
    update_transfer_status(db_conn, transfer_id, "active");
    send_file_offer(swarm, wire, transfer_id);
}

fn send_file_offer(swarm: &mut Swarm<DropleBehaviour>, wire: &mut WireState, transfer_id: &str) {
    let Some(transfer) = wire.outbound.get(transfer_id) else {
        return;
    };
    let peer = transfer.peer;
    let request = WireMessage::FileOffer {
        transfer_id: transfer_id.to_string(),
        file_name: transfer.file_name.clone(),
        file_size: transfer.file_size,
        file_hash: transfer.file_hash.clone(),
    };
    let request_id = swarm.behaviour_mut().wire.send_request(&peer, request);
    wire.pending.insert(
        request_id,
        PendingAction {
            transfer_id: transfer_id.to_string(),
            kind: PendingKind::Offer,
        },
    );
}

fn resume_transfer(
    swarm: &mut Swarm<DropleBehaviour>,
    wire: &mut WireState,
    db_conn: &Option<Connection>,
    transfer_id: &str,
) {
    let Some(transfer) = wire.outbound.get(transfer_id) else {
        return;
    };
    if wire.pending.values().any(|a| a.transfer_id == transfer_id) {
        return;
    }
    if transfer.offer_acked {
        update_transfer_status(db_conn, transfer_id, "active");
        send_next_chunk(swarm, wire, db_conn, transfer_id);
    } else {
        update_transfer_status(db_conn, transfer_id, "active");
        send_file_offer(swarm, wire, transfer_id);
    }
}

fn resume_peer_transfers(
    swarm: &mut Swarm<DropleBehaviour>,
    wire: &mut WireState,
    db_conn: &Option<Connection>,
    peer: &PeerId,
) {
    let pending: Vec<String> = wire
        .pending
        .values()
        .map(|a| a.transfer_id.clone())
        .collect();
    let ids: Vec<String> = wire
        .outbound
        .iter()
        .filter(|(id, t)| t.peer == *peer && !pending.contains(id))
        .map(|(id, _)| id.clone())
        .collect();
    for id in ids {
        resume_transfer(swarm, wire, db_conn, &id);
    }
}

fn send_next_chunk(
    swarm: &mut Swarm<DropleBehaviour>,
    wire: &mut WireState,
    db_conn: &Option<Connection>,
    transfer_id: &str,
) {
    let Some(transfer) = wire.outbound.get_mut(transfer_id) else {
        return;
    };

    if transfer.next_index >= transfer.chunks.len() {
        let request_id = swarm.behaviour_mut().wire.send_request(
            &transfer.peer,
            WireMessage::FileDone {
                transfer_id: transfer_id.to_string(),
            },
        );
        wire.pending.insert(
            request_id,
            PendingAction {
                transfer_id: transfer_id.to_string(),
                kind: PendingKind::Done,
            },
        );
        return;
    }

    let chunk = transfer.chunks[transfer.next_index].clone();
    transfer.next_index += 1;
    let peer = transfer.peer;
    let total = transfer.chunks.len() as u32;
    let progress: i64 = transfer.chunks[..transfer.next_index]
        .iter()
        .map(|c| c.size() as i64)
        .sum();

    let request_id = swarm.behaviour_mut().wire.send_request(
        &peer,
        WireMessage::FileChunk {
            transfer_id: transfer_id.to_string(),
            index: chunk.chunk_index,
            total,
            chunk_hash: chunk.hash.clone(),
            data: B64.encode(&chunk.data),
        },
    );
    wire.pending.insert(
        request_id,
        PendingAction {
            transfer_id: transfer_id.to_string(),
            kind: PendingKind::Chunk,
        },
    );
    set_transfer_progress(db_conn, transfer_id, progress);
}

fn send_pairing_request(swarm: &mut Swarm<DropleBehaviour>, wire: &mut WireState, peer: PeerId) {
    let request_id = swarm
        .behaviour_mut()
        .wire
        .send_request(&peer, WireMessage::PairingRequest);
    wire.pairing_requests.insert(request_id, peer);
}

fn handle_wire_event(
    event: request_response::Event<WireMessage, WireMessage>,
    shared: &Arc<Mutex<SharedState>>,
    db_conn: &Option<Connection>,
    swarm: &mut Swarm<DropleBehaviour>,
    wire: &mut WireState,
) {
    match event {
        request_response::Event::Message { peer, message, .. } => match message {
            ReqResMessage::Request {
                request, channel, ..
            } => {
                if matches!(request, WireMessage::PairingRequest) {
                    let id = peer.to_string();
                    if let Ok(mut state) = shared.lock() {
                        state.pending_approvals.insert(id.clone(), id.clone());
                        state.rejected_peers.remove(&id);
                    }
                    wire.pairing_inbound.insert(id, channel);
                    return;
                }
                let response = handle_incoming_request(request, &peer, shared, db_conn, wire);
                let _ = swarm.behaviour_mut().wire.send_response(channel, response);
            }
            ReqResMessage::Response {
                request_id,
                response,
                ..
            } => handle_wire_response(request_id, response, shared, db_conn, swarm, wire),
        },
        request_response::Event::OutboundFailure {
            request_id, error, ..
        } => {
            let _ = error;
            let Some(action) = wire.pending.remove(&request_id) else {
                return;
            };
            if action.kind == PendingKind::Chunk {
                if let Some(transfer) = wire.outbound.get_mut(&action.transfer_id) {
                    transfer.next_index = transfer.next_index.saturating_sub(1);
                }
            }
            let Some(peer) = wire.outbound.get(&action.transfer_id).map(|t| t.peer) else {
                mark_transfer_failed(db_conn, &action.transfer_id);
                return;
            };
            update_transfer_status(db_conn, &action.transfer_id, "pending");
            let connected = shared
                .lock()
                .map(|s| {
                    s.peers
                        .get(&peer.to_string())
                        .map(|p| p.connected)
                        .unwrap_or(false)
                })
                .unwrap_or(false);
            if connected {
                resume_transfer(swarm, wire, db_conn, &action.transfer_id);
            }
        }
        _ => {}
    }
}

fn handle_wire_response(
    request_id: request_response::OutboundRequestId,
    response: WireMessage,
    shared: &Arc<Mutex<SharedState>>,
    db_conn: &Option<Connection>,
    swarm: &mut Swarm<DropleBehaviour>,
    wire: &mut WireState,
) {
    match response {
        WireMessage::PairingResult { accepted } => {
            if let Some(peer) = wire.pairing_requests.remove(&request_id) {
                if !accepted {
                    if let Ok(mut state) = shared.lock() {
                        state.pairing_notifications.push((peer.to_string(), false));
                    }
                    let _ = swarm.disconnect_peer_id(peer);
                }
            }
        }
        // Catatan bersifat lokal per perangkat; delta dari peer tidak diterapkan.
        WireMessage::Sync { .. } => {}
        WireMessage::Ack { ok, message } => {
            let Some(action) = wire.pending.remove(&request_id) else {
                return;
            };
            if !ok {
                if wire.outbound.contains_key(&action.transfer_id)
                    && message.contains("tidak dikenal")
                {
                    if let Some(transfer) = wire.outbound.get_mut(&action.transfer_id) {
                        transfer.next_index = 0;
                        transfer.offer_acked = false;
                    }
                    update_transfer_status(db_conn, &action.transfer_id, "pending");
                    send_file_offer(swarm, wire, &action.transfer_id);
                    return;
                }
                let _ = wire.outbound.remove(&action.transfer_id);
                mark_transfer_failed(db_conn, &action.transfer_id);
                return;
            }
            match action.kind {
                PendingKind::Offer => {
                    if let Some(transfer) = wire.outbound.get_mut(&action.transfer_id) {
                        transfer.offer_acked = true;
                    }
                    send_next_chunk(swarm, wire, db_conn, &action.transfer_id);
                }
                PendingKind::Chunk => {
                    send_next_chunk(swarm, wire, db_conn, &action.transfer_id);
                }
                PendingKind::Done => {
                    if let Some(done) = wire.outbound.remove(&action.transfer_id) {
                        update_transfer_status(db_conn, &action.transfer_id, "completed");
                        set_transfer_progress(db_conn, &action.transfer_id, done.file_size);
                    }
                }
            }
        }
        _ => {}
    }
}

fn handle_incoming_request(
    request: WireMessage,
    peer: &PeerId,
    shared: &Arc<Mutex<SharedState>>,
    db_conn: &Option<Connection>,
    wire: &mut WireState,
) -> WireMessage {
    match request {
        WireMessage::PairingRequest => {
            let id = peer.to_string();
            if let Ok(mut state) = shared.lock() {
                state.pending_approvals.insert(id.clone(), id.clone());
                state.rejected_peers.remove(&id);
            }
            WireMessage::nack("permintaan harus diproses oleh handler pairing")
        }
        WireMessage::PairingResult { .. } => {
            WireMessage::nack("respons pairing tidak valid sebagai permintaan")
        }
        WireMessage::Sync { .. } => {
            WireMessage::nack("sinkronisasi catatan antar perangkat dinonaktifkan".to_string())
        }
        WireMessage::FileOffer {
            transfer_id,
            file_name,
            file_size,
            file_hash,
        } => {
            let blocked = shared
                .lock()
                .map(|state| {
                    state.pending_approvals.contains_key(&peer.to_string())
                        || state.rejected_peers.contains(&peer.to_string())
                })
                .unwrap_or(false);
            if blocked {
                return WireMessage::nack("koneksi belum diizinkan");
            }
            if wire.incoming.contains_key(&transfer_id) {
                return WireMessage::ack("sudah diterima");
            }
            match prepare_incoming(
                db_conn,
                peer,
                &transfer_id,
                &file_name,
                file_size,
                &file_hash,
            ) {
                Ok(incoming) => {
                    wire.incoming.insert(transfer_id, incoming);
                    WireMessage::ack("offer diterima")
                }
                Err(e) => WireMessage::nack(e.to_string()),
            }
        }
        WireMessage::FileChunk {
            transfer_id,
            index,
            total,
            chunk_hash,
            data,
        } => {
            let _ = total;
            let Some(incoming) = wire.incoming.get_mut(&transfer_id) else {
                return WireMessage::nack("transfer tidak dikenal");
            };
            let bytes = match B64.decode(data.as_bytes()) {
                Ok(bytes) => bytes,
                Err(_) => return WireMessage::nack("chunk bukan base64 valid"),
            };
            let actual = sha256_hex(&bytes);
            if actual != chunk_hash {
                return WireMessage::nack("hash chunk tidak cocok");
            }
            if incoming.received.contains(&index) {
                return WireMessage::ack("chunk sudah diterima");
            }
            let offset = index as u64 * chunking::CHUNK_SIZE as u64;
            if let Err(e) = incoming.file.seek(SeekFrom::Start(offset)) {
                return WireMessage::nack(e.to_string());
            }
            if let Err(e) = incoming.file.write_all(&bytes) {
                return WireMessage::nack(e.to_string());
            }
            incoming.hasher.update(&bytes);
            incoming.received.insert(index);
            incoming.written += bytes.len() as i64;
            set_transfer_progress(db_conn, &transfer_id, incoming.written);
            WireMessage::ack("chunk diterima")
        }
        WireMessage::FileDone { transfer_id } => {
            let Some(incoming) = wire.incoming.remove(&transfer_id) else {
                return WireMessage::nack("transfer tidak dikenal");
            };
            let actual = hex_digest(incoming.hasher.finalize());
            drop(incoming.file);
            if !incoming.expected_hash.is_empty() && actual != incoming.expected_hash {
                update_transfer_status(db_conn, &transfer_id, "failed");
                return WireMessage::nack("hash file tidak cocok");
            }
            update_transfer_status(db_conn, &transfer_id, "completed");
            WireMessage::ack("transfer selesai")
        }
        WireMessage::Ack { .. } => WireMessage::ack("ok"),
    }
}

fn prepare_incoming(
    db_conn: &Option<Connection>,
    peer: &PeerId,
    transfer_id: &str,
    file_name: &str,
    file_size: i64,
    file_hash: &str,
) -> Result<IncomingTransfer> {
    let safe_name = Path::new(file_name)
        .file_name()
        .and_then(|n| n.to_str())
        .filter(|n| !n.is_empty())
        .unwrap_or("drople-file");
    let dir = receive_dir(db_conn)?;
    std::fs::create_dir_all(&dir)
        .map_err(|e| DropleError::Internal(format!("gagal membuat folder terima: {e}")))?;
    let mut path = dir.join(safe_name);
    if path.exists() {
        path = dir.join(format!("{transfer_id}-{safe_name}"));
    }

    let file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(&path)
        .map_err(|e| DropleError::Internal(format!("gagal membuat file tujuan: {e}")))?;

    if let Some(conn) = db_conn {
        let exists = db::get_file_transfer(conn, transfer_id).is_ok();
        if !exists {
            db::create_file_transfer(
                conn,
                transfer_id,
                &peer.to_string(),
                safe_name,
                file_size,
                file_hash,
                "receive",
            )?;
        }
        db::set_file_transfer_local_path(conn, transfer_id, &path.to_string_lossy())?;
        db::update_file_transfer_status(conn, transfer_id, "active")?;
    }

    Ok(IncomingTransfer {
        file,
        hasher: Sha256::new(),
        expected_hash: file_hash.to_string(),
        written: 0,
        received: std::collections::HashSet::new(),
    })
}

fn receive_dir(db_conn: &Option<Connection>) -> Result<PathBuf> {
    if let Some(conn) = db_conn {
        if let Some(dir) = db::get_setting(conn, RECEIVE_DIR_SETTING)? {
            if !dir.trim().is_empty() {
                return Ok(PathBuf::from(dir));
            }
        }
    }
    Ok(std::env::temp_dir().join("drople-downloads"))
}

fn update_transfer_status(db_conn: &Option<Connection>, transfer_id: &str, status: &str) {
    if let Some(conn) = db_conn {
        let _ = db::update_file_transfer_status(conn, transfer_id, status);
    }
}

fn set_transfer_progress(db_conn: &Option<Connection>, transfer_id: &str, progress: i64) {
    if let Some(conn) = db_conn {
        let _ = db::update_file_transfer_progress(conn, transfer_id, progress);
    }
}

fn mark_transfer_failed(db_conn: &Option<Connection>, transfer_id: &str) {
    if let Some(conn) = db_conn {
        let _ = db::update_file_transfer_status(conn, transfer_id, "failed");
    }
}

fn sha256_hex(data: &[u8]) -> String {
    hex_digest(Sha256::digest(data))
}

fn hex_digest(digest: impl AsRef<[u8]>) -> String {
    digest.as_ref().iter().map(|b| format!("{b:02x}")).collect()
}

fn dial_peer(
    swarm: &mut Swarm<DropleBehaviour>,
    peer_id: &str,
    addrs: &[String],
    relay_addr: Option<&Multiaddr>,
) {
    let Ok(target) = peer_id.parse::<PeerId>() else {
        return;
    };

    for raw in addrs {
        let Ok(mut addr) = raw.parse::<Multiaddr>() else {
            continue;
        };
        if !addr.iter().any(|p| matches!(p, Protocol::P2p(_))) {
            addr.push(Protocol::P2p(target));
        }
        let _ = swarm.dial(addr);
    }

    if let Some(relay) = relay_addr {
        if let Ok(addr) = format!("{relay}/p2p-circuit/p2p/{target}").parse::<Multiaddr>() {
            let _ = swarm.dial(addr);
        }
    }
}

/// Membuat kode pairing untuk handle, dipakai test.
pub fn pairing_code_for(handle: &NodeHandle) -> String {
    let state = handle.snapshot();
    pairing::new_code(
        state.local_peer_id,
        state.listen_addrs,
        state.local_fingerprint,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tcp_loopback_addr(handle: &NodeHandle) -> Option<String> {
        handle
            .snapshot()
            .listen_addrs
            .into_iter()
            .find(|a| a.starts_with("/ip4/127.0.0.1/tcp/"))
    }

    #[test]
    fn two_nodes_connect_over_loopback() {
        let node_a =
            spawn(Keypair::generate_ed25519(), None, "Test Device".into()).expect("spawn A");
        node_a.wait_listen_addr(Duration::from_secs(5));
        let addr = tcp_loopback_addr(&node_a).expect("A punya listen addr");

        let node_b =
            spawn(Keypair::generate_ed25519(), None, "Test Device".into()).expect("spawn B");
        node_b.wait_listen_addr(Duration::from_secs(5));
        node_b.dial_addr(&addr);

        let started = std::time::Instant::now();
        let mut connected = false;
        while started.elapsed() < Duration::from_secs(10) {
            if node_b.snapshot().peers.values().any(|p| p.connected) {
                connected = true;
                break;
            }
            std::thread::sleep(Duration::from_millis(50));
        }

        node_b.stop();
        node_a.stop();
        assert!(connected, "node B harus terhubung ke node A via loopback");
    }

    #[test]
    fn file_transfer_over_wire() {
        let dir = tempfile::tempdir().expect("tempdir");
        let recv_dir = dir.path().join("recv");
        std::fs::create_dir_all(&recv_dir).expect("recv dir");
        let db_path = dir.path().join("receiver.db");
        {
            let conn = Connection::open(&db_path).expect("db");
            db::init_schema(&conn).expect("schema");
            db::set_setting(&conn, RECEIVE_DIR_SETTING, &recv_dir.to_string_lossy())
                .expect("setting");
        }

        let source = dir.path().join("hello.txt");
        let content = b"Hello from Drople file transfer!";
        std::fs::write(&source, content).expect("source");

        let node_a =
            spawn(Keypair::generate_ed25519(), None, "Test Device".into()).expect("spawn A");
        node_a.wait_listen_addr(Duration::from_secs(5));
        let node_b = spawn(
            Keypair::generate_ed25519(),
            Some(db_path.to_string_lossy().to_string()),
            "Receiver".into(),
        )
        .expect("spawn B");
        node_b.wait_listen_addr(Duration::from_secs(5));

        let addr_b = tcp_loopback_addr(&node_b).expect("B addr");
        node_a.dial_peer(node_b.local_peer_id(), &[addr_b]);

        let started = std::time::Instant::now();
        while started.elapsed() < Duration::from_secs(10) {
            if node_a
                .snapshot()
                .peers
                .get(node_b.local_peer_id())
                .map(|p| p.connected)
                .unwrap_or(false)
            {
                break;
            }
            std::thread::sleep(Duration::from_millis(50));
        }

        node_a.send_file(
            node_b.local_peer_id(),
            "transfer-test",
            &source.to_string_lossy(),
        );

        let target = recv_dir.join("hello.txt");
        let mut ok = false;
        let started = std::time::Instant::now();
        while started.elapsed() < Duration::from_secs(15) {
            if std::fs::read(&target)
                .map(|d| d == content)
                .unwrap_or(false)
            {
                ok = true;
                break;
            }
            std::thread::sleep(Duration::from_millis(100));
        }

        node_a.stop();
        node_b.stop();
        assert!(ok, "file harus diterima dan isinya sama");
    }

    #[test]
    #[ignore = "butuh multicast mDNS aktif di jaringan lokal"]
    fn two_nodes_discover_via_mdns() {
        let node_a =
            spawn(Keypair::generate_ed25519(), None, "Test Device".into()).expect("spawn A");
        let node_b =
            spawn(Keypair::generate_ed25519(), None, "Test Device".into()).expect("spawn B");

        let peer_a = node_a.local_peer_id().to_string();
        let started = std::time::Instant::now();
        let mut discovered = false;
        while started.elapsed() < Duration::from_secs(15) {
            if node_b.snapshot().peers.contains_key(&peer_a) {
                discovered = true;
                break;
            }
            std::thread::sleep(Duration::from_millis(100));
        }

        node_b.stop();
        node_a.stop();
        assert!(discovered, "node B harus menemukan node A via mDNS");
    }
}
