#include "server.h"

void origen_server() {
  int complete = 0;
  while(!complete) {
    for (int x=0; x < 10; x++) {
      vpi_printf("Simulation running!\n");
    }
    complete = 1;
  }
  return;
}
