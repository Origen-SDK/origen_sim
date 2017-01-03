///
/// This implements the bridge between Origen and the simulation, it implements a
/// simple string-based message protocol for communicating between the two domains
///
#include "bridge.h"
#include "client.h"
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>

static int period_in_ns;
static void bridge_cycle(void);
static void bridge_drive_pin(char*, char*);
static void bridge_compare_pin(char*, char*);
static void bridge_dont_care_pin(char*);
static void bridge_set_net(char*, uint32_t);
static void bridge_apply_waveform(int, char, int);
static void register_waveform_events(void);
static long repeat;

typedef struct Event {
  int time;
  char data;
} Event;

typedef struct Waveform {
  char * pin;
  vpiHandle control;     // A handle to the driver control register
  vpiHandle force_data;  // A handle to the driver force_data register
  Event events[10];
} Waveform;

static Waveform * waveforms = NULL;
static int number_of_waveforms = 0;

/// Example waveform message:
///   "2^clock^0^D^25^0^50^D^75^0^END^tck^0^D^50^0^END"
void bridge_define_waveforms(char * waves) {
  char *token;

  if (waveforms) {
    // TODO: Should free the memory for the pin names first
    free(waveforms);
    number_of_waveforms = 0;
  }

  // strtok needs a writable copy of waves
  char * mywaves = (char *) malloc(strlen(waves) + 1);
  strcpy(mywaves, waves);

  // First in the stream is the amount of pins that have waveforms, get it and prepare
  // the space for them
  token = strtok(mywaves, "^");
  number_of_waveforms = (int)strtol(token, NULL, 10);
  waveforms = (Waveform *) malloc(number_of_waveforms * sizeof(Waveform));

  for (int i = 0; i < number_of_waveforms; i++) {
    token = strtok(NULL, "^");
    waveforms[i].pin = (char *) malloc(strlen(token) + 1);
    strcpy(waveforms[i].pin, token);

    char * driver = (char *) malloc(strlen(token) + 16);
    strcpy(driver, "origen_tb.pins.");
    strcat(driver, token);

    char * control = (char *) malloc(strlen(driver) + 16);
    strcpy(control, driver);
    strcat(control, ".control");
    waveforms[i].control = vpi_handle_by_name(control, NULL);
    free(control);

    char * force = (char *) malloc(strlen(driver) + 16);
    strcpy(force, driver);
    strcat(force, ".force_data");
    waveforms[i].force_data = vpi_handle_by_name(force, NULL);
    free(force);

    int x = 0;
    token = strtok(NULL, "^");
    while (strcmp(token, "END") != 0) {
      waveforms[i].events[x].time = (int)strtol(token, NULL, 10);
      token = strtok(NULL, "^");
      waveforms[i].events[x].data = token[0];
      token = strtok(NULL, "^");
      x++;
    }
    waveforms[i].events[x].data = 'S'; // Indicate that there are no more events
  }
  free(mywaves);
}


static void register_waveform_events() {
  s_vpi_value v = {vpiIntVal, {0}};

  if (waveforms) {
    for (int i = 0; i < number_of_waveforms; i++) {

      int x = 0;

      while (waveforms[i].events[x].data != 'S') {
        int time;
        int data;

        time = waveforms[i].events[x].time;

        switch(waveforms[i].events[x].data) {
          case '0' :
            data = 1;
            break;
          case '1' :
            data = 2;
            break;
          case 'D' :
            data = 0;
            break;
          default :
            data = 0;
            break;
        }
        if (time == 0) {
          v.value.integer = data;
          vpi_put_value(waveforms[i].force_data, &v, NULL, vpiNoDelay);
        } else {
          bridge_apply_waveform(i, data + '0', time);
        }
        x++;
      }
    }
  }
}


/// This is called first upon a simulation start and it will block until it receives
/// a set_timeset message from Origen
void bridge_set_period(char * p_in_ns) {
  int p = (int) strtol(p_in_ns, NULL, 10);
  period_in_ns = p;
}


/// Immediately drives the given pin to the given value
static void bridge_drive_pin(char * name, char * val) {
  char * net = (char *) malloc(strlen(name) + 25);
  strcpy(net, "origen_tb.pins.");
  strcat(net, name);
  strcat(net, ".control");

  bridge_set_net(net, 0x10 | (val[0] - '0'));

  free(net);
}


/// Immediately sets the given pin to compare against the given value
static void bridge_compare_pin(char * name, char * val) {
  char * net = (char *) malloc(strlen(name) + 25);
  strcpy(net, "origen_tb.pins.");
  strcat(net, name);
  strcat(net, ".control");

  bridge_set_net(net, 0x20 | (val[0] - '0'));

  free(net);
}


/// Immediately sets the given pin to don't compare
static void bridge_dont_care_pin(char * name) {
  char * net = (char *) malloc(strlen(name) + 25);
  strcpy(net, "origen_tb.pins.");
  strcat(net, name);
  strcat(net, ".control");

  bridge_set_net(net, 0);

  free(net);
}


/// Immediately sets the given net to the given value
static void bridge_set_net(char * path, uint32_t val) {
  s_vpi_value v = {vpiIntVal, {0}};
  vpiHandle net;

  net = vpi_handle_by_name(path, NULL);
  v.value.integer = val;
  vpi_put_value(net, &v, NULL, vpiNoDelay);
}


/// Callback handler to implement bridge_apply_waveform
PLI_INT32 bridge_apply_waveform_cb(p_cb_data data) {
  s_vpi_value v = {vpiIntVal, {0}};

  char *wave_index, *value;
  wave_index = strtok(data->user_data, "^");
  value = strtok(NULL, "^");

  v.value.integer = value[0] - '0';
  vpi_put_value(waveforms[strtol(wave_index, NULL, 10)].force_data, &v, NULL, vpiNoDelay);
  free(data->user_data);
  return 0;
}


/// Registers a callback to apply the given waveform during this cycle
static void bridge_apply_waveform(int wave, char data, int delay_in_ns) {
  s_cb_data call;
  s_vpi_time time;
  char buffer[16];

  snprintf(buffer, sizeof(buffer), "%d", wave);

  char * user_data = (char *) malloc(sizeof(buffer) + 8);
  strcpy(user_data, buffer);
  strcat(user_data, "^");
  int len = strlen(user_data);
  user_data[len] = data;
  user_data[len + 1] = '\0';
  // data will get freed by the callback

  time.type = vpiSimTime;
  time.high = (uint32_t)(0);
  time.low  = (uint32_t)(delay_in_ns);

  call.reason    = cbAfterDelay;
  call.cb_rtn    = bridge_apply_waveform_cb;
  call.obj       = 0;
  call.time      = &time;
  call.value     = 0;
  call.user_data = user_data;

  vpi_free_object(vpi_register_cb(&call));
}


/// Entry point to the bridge_wait_for_msg loop
///
/// This advances the simulator by 1 cycle to apply the initial values set by the
/// testbench, it will then signal to Origen that it is ready to start accepting
/// commands.
void bridge_init() {
  s_cb_data call;
  s_vpi_time time;

  time.type = vpiSimTime;
  time.high = (uint32_t)(0);
  time.low  = (uint32_t)(period_in_ns);

  call.reason    = cbAfterDelay;
  call.obj       = 0;
  call.time      = &time;
  call.value     = 0;
  call.user_data = 0;
  call.cb_rtn    = bridge_init_done;

  vpi_free_object(vpi_register_cb(&call));
}


PLI_INT32 bridge_init_done(p_cb_data data) {
  UNUSED(data);
  client_put("READY!\n");
  return bridge_wait_for_msg(NULL);
}


/// Waits and responds to instructions from Origen (to set pin states).
/// When Origen requests a cycle, time will be advanced and this func will be called again.
PLI_INT32 bridge_wait_for_msg(p_cb_data data) {
  UNUSED(data);
  int max_msg_len = 100;
  char msg[max_msg_len];
  int err;
  char *opcode, *arg1, *arg2;

  while(1) {

    err = client_get(max_msg_len, msg);
    if (err) {
      vpi_printf("ERROR: Failed to receive from Origen!\n");
      return 1;
    }

    opcode = strtok(msg, "^");

    switch(*opcode) {
      // Set Period
      //   1^100
      case '1' :
        arg1 = strtok(NULL, "^");
        bridge_set_period(arg1);
        break;
      // Drive Pin
      //   2^clock^0
      //   2^clock^1
      case '2' :
        arg1 = strtok(NULL, "^");
        arg2 = strtok(NULL, "^");
        bridge_drive_pin(arg1, arg2);
        break;
      // Cycle
      //   3^
      case '3' :
        arg1 = strtok(NULL, "^");
        repeat = strtol(arg1, NULL, 10) - 1;
        bridge_cycle();
        return 0;
      // Compare Pin
      //   4^tdo^0
      //   4^tdo^1
      case '4' :
        arg1 = strtok(NULL, "^");
        arg2 = strtok(NULL, "^");
        bridge_compare_pin(arg1, arg2);
        break;
      // Don't Care Pin
      //   5^tdo
      case '5' :
        arg1 = strtok(NULL, "^");
        bridge_dont_care_pin(arg1);
        break;
      // Sync-up
      //   Y^
      case 'Y' :
        client_put("OK!\n");
        break;
      // Complete
      //   Z^
      case 'Z' :
        return 0;
      default :
        vpi_printf("ERROR: Illegal opcode received!\n");
        return 1;
    }
  }
}


PLI_INT32 bridge_cycle_cb(p_cb_data data) {
  UNUSED(data);
  repeat = repeat - 1;
  bridge_cycle();
  return 0;
}


/// Registers a callback after a cycle period, the main server loop should unblock
/// after calling this to allow the simulation to proceed for a cycle
static void bridge_cycle() {
  s_cb_data call;
  s_vpi_time time;

  time.type = vpiSimTime;
  time.high = (uint32_t)(0);
  time.low  = (uint32_t)(period_in_ns);

  call.reason    = cbAfterDelay;
  call.obj       = 0;
  call.time      = &time;
  call.value     = 0;
  call.user_data = 0;

  if (repeat) {
    call.cb_rtn    = bridge_cycle_cb;
  } else {
    call.cb_rtn    = bridge_wait_for_msg;
  }

  vpi_free_object(vpi_register_cb(&call));

  register_waveform_events();
}
