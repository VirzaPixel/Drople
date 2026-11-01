use serde::Serialize;

use crate::net::node::PeerEntry;

#[derive(Debug, Clone, Serialize)]
pub struct PeerView {
    #[serde(flatten)]
    pub peer: PeerEntry,
}

pub fn to_json(peers: Vec<PeerEntry>) -> crate::error::Result<String> {
    let views: Vec<PeerView> = peers.into_iter().map(|peer| PeerView { peer }).collect();
    Ok(serde_json::to_string(&views)?)
}
