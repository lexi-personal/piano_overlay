#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "my_application.h"

// True when the process is running inside WSL.
static bool running_under_wsl() {
  if (getenv("WSL_DISTRO_NAME") != nullptr) return true;
  if (getenv("WSL_INTEROP") != nullptr) return true;

  FILE* version = fopen("/proc/version", "r");
  if (version == nullptr) return false;

  char buffer[512];
  size_t read = fread(buffer, 1, sizeof(buffer) - 1, version);
  fclose(version);
  buffer[read] = '\0';

  return strstr(buffer, "microsoft") != nullptr ||
         strstr(buffer, "Microsoft") != nullptr ||
         strstr(buffer, "WSL") != nullptr;
}

// WSLg routes OpenGL through a Direct3D 12 translation layer
// (`libd3d12core.so` / `libnvwgf2umx.so`). Flutter's compositor deadlocks
// against it: the Dart isolate goes idle, the GTK main loop sits in `poll`,
// and the window keeps showing a stale frame forever, so the app looks frozen
// even though nothing in Dart is blocked.
//
// Forcing Mesa's software rasteriser avoids that driver entirely. It has to
// happen before GTK touches GL, which is why it lives here rather than in
// Dart. Set `PIANO_OVERLAY_GPU=1` to opt back into the GPU driver.
static void configure_gl_backend() {
  const char* force_gpu = getenv("PIANO_OVERLAY_GPU");
  if (force_gpu != nullptr && strcmp(force_gpu, "1") == 0) return;

  if (!running_under_wsl()) return;

  // Never override a value the user set themselves.
  setenv("LIBGL_ALWAYS_SOFTWARE", "1", 0);
}

int main(int argc, char** argv) {
  configure_gl_backend();

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
