#include "my_application.h"
#include <cstdlib>

int main(int argc, char** argv) {
  // Cegah GTK crash karena schema org.gnome.settings-daemon.plugins.xsettings
  // yang tidak lengkap / versi berbeda di distro Linux tertentu.
  setenv("GSETTINGS_BACKEND", "keyfile", 0);

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
