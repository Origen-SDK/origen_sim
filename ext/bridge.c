///
/// This implements the bridge between Origen and the simulation, it implements a
/// simple string-based message protocol for communicating between the two domains
///
#include "bridge.h"
#include "client.h"
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>

#define MAX_NUMBER_PINS 2000
#define MAX_WAVE_EVENTS 10

typedef struct Pin {
  vpiHandle data;        // A handle to the driver data register
  vpiHandle drive;       // A handle to the driver drive enable register
  vpiHandle force_data;  // A handle to the driver force_data register
  vpiHandle compare;     // A handle to the driver compare enable register
  int drive_wave;        // Index of the drive wave to be used for this pin
  int compare_wave;      // Index of the compare wave to be used for this pin
  int drive_wave_pos;    // Position of the pin in the drive_wave's active pin array
  int compare_wave_pos;  // Position of the pin in the compare_wave's active pin array
  int index;             // The pin's index in the pins array
  int previous_state;    // Used to keep track of whether the pin was previously driving or comparing
} Pin;

typedef struct Event {
  int time;
  char data;
} Event;

typedef struct Wave {
  Event events[MAX_WAVE_EVENTS];
  Pin *active_pins[MAX_NUMBER_PINS];
  int active_pin_count;
} Wave;

static int period_in_ns;
static long repeat = 0;
static Pin pins[MAX_NUMBER_PINS];
static int number_of_pins = 0;
// Allocate space for a unique wave for each pin, in reality it will be much less
static Wave drive_waves[MAX_NUMBER_PINS];
static int number_of_drive_waves = 0;
static Wave compare_waves[MAX_NUMBER_PINS];
static int number_of_compare_waves = 0;
static int runtime_errors = 0;

static void bridge_set_period(char*);
static void bridge_define_pin(char*, char*, char*, char*);
static void bridge_define_wave(char*, char*, char*);
static void bridge_cycle(void);
static void bridge_drive_pin(char*, char*);
static void bridge_compare_pin(char*, char*);
static void bridge_dont_care_pin(char*);
static void bridge_register_wave_events(void);
static void bridge_register_wave_event(int, int, int, int);
static void bridge_enable_drive_wave(Pin*);
static void bridge_disable_drive_wave(Pin*);
static void bridge_enable_compare_wave(Pin*);
static void bridge_disable_compare_wave(Pin*);

static void bridge_define_pin(char * name, char * pin_ix, char * drive_wave_ix, char * compare_wave_ix) {
  int index = atoi(pin_ix);
  Pin *pin = &pins[index];
  number_of_pins += 1;

  (*pin).index = index;
  (*pin).drive_wave = atoi(drive_wave_ix);
  (*pin).compare_wave = atoi(compare_wave_ix);
  (*pin).previous_state = 0;

  char * driver = (char *) malloc(strlen(name) + 16);
  strcpy(driver, "origen_tb.pins.");
  strcat(driver, name);

  char * data = (char *) malloc(strlen(driver) + 16);
  strcpy(data, driver);
  strcat(data, ".data");
  (*pin).data = vpi_handle_by_name(data, NULL);
  free(data);

  char * drive = (char *) malloc(strlen(driver) + 16);
  strcpy(drive, driver);
  strcat(drive, ".drive");
  (*pin).drive = vpi_handle_by_name(drive, NULL);
  free(drive);

  char * force = (char *) malloc(strlen(driver) + 16);
  strcpy(force, driver);
  strcat(force, ".force_data");
  (*pin).force_data = vpi_handle_by_name(force, NULL);
  free(force);

  char * compare = (char *) malloc(strlen(driver) + 16);
  strcpy(compare, driver);
  strcat(compare, ".compare");
  (*pin).compare = vpi_handle_by_name(compare, NULL);
  free(compare);

  free(driver);
}


static void bridge_define_wave(char * index, char * compare, char * events) {
  int ix = atoi(index);
  Wave * wave;
 
  if (compare[0] == '0') {
    wave = &drive_waves[ix];
    number_of_drive_waves += 1;
  } else {
    wave = &compare_waves[ix];
    number_of_compare_waves += 1;
  }
 
  char * token;
  // strtok needs a writable copy of events
  char * myevents = (char *) malloc(strlen(events) + 1);
  strcpy(myevents, events);

  int i = 0;
  token = strtok(myevents, "_");

  while (token != NULL) {
    (*wave).events[i].time = (int)strtol(token, NULL, 10);
    token = strtok(NULL, "_");
    (*wave).events[i].data = token[0];
    token = strtok(NULL, "_");
    i++;
  }
  (*wave).events[i].data = 'S'; // Indicate that there are no more events
  free(myevents);
  (*wave).active_pin_count = 0;
}


static void bridge_register_wave_events() {
  if (number_of_drive_waves) {
    for (int i = 1; i < number_of_drive_waves; i++) {

      if (drive_waves[i].active_pin_count) {
        int x = 0;

        while (drive_waves[i].events[x].data != 'S') {
          int time;

          time = drive_waves[i].events[x].time;

          // TODO: May save some time by calling directly at time 0
          //if (time == 0) {
          //} else {
            bridge_register_wave_event(i, x, 0, time);
          //}
          x++;
        }
      }
    }
  }

  for (int i = 0; i < number_of_compare_waves; i++) {

    if (compare_waves[i].active_pin_count) {
      int x = 0;

      while (compare_waves[i].events[x].data != 'S') {
        int time;

        time = compare_waves[i].events[x].time;

        // TODO: May save some time by calling directly at time 0
        //if (time == 0) {
        //} else {
          bridge_register_wave_event(i, x, 1, time);
        //}
        x++;
      }
    }
  }
}

static void bridge_enable_drive_wave(Pin * pin) {
  Wave *wave = &drive_waves[(*pin).drive_wave];

  (*wave).active_pins[(*wave).active_pin_count] = pin;
  (*pin).drive_wave_pos = (*wave).active_pin_count;
  (*wave).active_pin_count += 1;
}

static void bridge_disable_drive_wave(Pin * pin) {
  Wave *wave = &compare_waves[(*pin).drive_wave];

  // If pin is last, we can clear it by just decrementing the active pin counter
  if ((*pin).drive_wave_pos != (*wave).active_pin_count - 1) {
    // Otherwise we can remove it by overwriting it with the current last pin in the
    // array, since the order is not important
    (*wave).active_pins[(*pin).drive_wave_pos] = (*wave).active_pins[(*wave).active_pin_count - 1];
    // Need to let the moved pin know its new position
    (*(*wave).active_pins[(*pin).drive_wave_pos]).drive_wave_pos = (*pin).drive_wave_pos;
  }

  (*wave).active_pin_count -= 1;
}

static void bridge_enable_compare_wave(Pin * pin) {
  Wave *wave = &compare_waves[(*pin).compare_wave];

  (*wave).active_pins[(*wave).active_pin_count] = pin;
  (*pin).compare_wave_pos = (*wave).active_pin_count;
  (*wave).active_pin_count += 1;
}

static void bridge_disable_compare_wave(Pin * pin) {
  Wave *wave = &compare_waves[(*pin).compare_wave];

  // If pin is last, we can clear it by just decrementing the active pin counter
  if ((*pin).compare_wave_pos != (*wave).active_pin_count - 1) {
    // Otherwise we can remove it by overwriting it with the current last pin in the
    // array, since the order is not important
    (*wave).active_pins[(*pin).compare_wave_pos] = (*wave).active_pins[(*wave).active_pin_count - 1];
    // Need to let the moved pin know its new position
    (*(*wave).active_pins[(*pin).compare_wave_pos]).compare_wave_pos = (*pin).compare_wave_pos;
  }

  (*wave).active_pin_count -= 1;
}


static void bridge_set_period(char * p_in_ns) {
  int p = (int) strtol(p_in_ns, NULL, 10);
  period_in_ns = p;
}


/// Immediately drives the given pin to the given value
static void bridge_drive_pin(char * index, char * val) {
  Pin *pin = &pins[atoi(index)];
  s_vpi_value v = {vpiIntVal, {0}};

  // Apply the data value to the pin's driver
  v.value.integer = (val[0] - '0');
  vpi_put_value((*pin).data, &v, NULL, vpiNoDelay);
  v.value.integer = 1;
  vpi_put_value((*pin).drive, &v, NULL, vpiNoDelay);
  // Make sure not comparing
  v.value.integer = 0;
  vpi_put_value((*pin).compare, &v, NULL, vpiNoDelay);

  // Register it as actively driving with it's wave
  
  // If it is already driving the wave will already be setup
  if ((*pin).previous_state != 1) {
    // Wave 0 means drive for the whole cycle and there are no events
    // to register for
    if ((*pin).drive_wave != 0) {
      bridge_enable_drive_wave(pin);
    }
    if ((*pin).previous_state == 2) {
      bridge_disable_compare_wave(pin);
    }
    (*pin).previous_state = 1;
  }
}


/// Immediately sets the given pin to compare against the given value
static void bridge_compare_pin(char * index, char * val) {
  Pin *pin = &pins[atoi(index)];
  s_vpi_value v = {vpiIntVal, {0}};

  // Apply the data value to the pin's driver, don't enable compare yet,
  // the wave will do that later
  v.value.integer = (val[0] - '0');
  vpi_put_value((*pin).data, &v, NULL, vpiNoDelay);
  // Make sure not driving
  v.value.integer = 0;
  vpi_put_value((*pin).drive, &v, NULL, vpiNoDelay);

  // Register it as actively comparing with it's wave
  
  // If it is already comparing the wave will already be setup
  if ((*pin).previous_state != 2) {
    bridge_enable_compare_wave(pin);
    if ((*pin).previous_state == 1) {
      bridge_disable_drive_wave(pin);
    }
    (*pin).previous_state = 2;
  }
}


/// Immediately sets the given pin to don't compare
static void bridge_dont_care_pin(char * index) {
  Pin *pin = &pins[atoi(index)];
  s_vpi_value v = {vpiIntVal, {0}};

  // Disable drive and compare on the pin's driver
  v.value.integer = 0;
  vpi_put_value((*pin).drive, &v, NULL, vpiNoDelay);
  vpi_put_value((*pin).compare, &v, NULL, vpiNoDelay);

  if ((*pin).previous_state != 0) {
    if ((*pin).previous_state == 1) {
      bridge_disable_drive_wave(pin);
    }
    if ((*pin).previous_state == 2) {
      bridge_disable_compare_wave(pin);
    }
    (*pin).previous_state = 0;
  }
}


/// Callback handler to implement the events registered by bridge_register_wave_event
PLI_INT32 bridge_apply_wave_event_cb(p_cb_data data) {
  s_vpi_value v = {vpiIntVal, {0}};

  int * wave_ix  = (int*)(&(data->user_data[0]));
  int * event_ix = (int*)(&(data->user_data[sizeof(int)]));
  int * compare  = (int*)(&(data->user_data[sizeof(int) * 2]));

  Wave * wave;

  if (*compare) {
    wave = &compare_waves[*wave_ix];

    int d;
    switch((*wave).events[*event_ix].data) {
      case 'C' :
        d = 1;
        break;
      case 'X' :
        d = 0;
        break;
      default :
        vpi_printf("ERROR: Unknown compare event: %c", (*wave).events[*event_ix].data);
        runtime_errors += 1;
        return 1;
    }

    v.value.integer = d;
    for (int i = 0; i < (*wave).active_pin_count; i++) {
      vpi_put_value((*(*wave).active_pins[i]).compare, &v, NULL, vpiNoDelay);
    }


  } else {
    wave = &drive_waves[*wave_ix];

    int d;
    switch((*wave).events[*event_ix].data) {
      case '0' :
        d = 1;
        break;
      case '1' :
        d = 2;
        break;
      case 'D' :
        d = 0;
        break;
      default :
        vpi_printf("ERROR: Unknown drive event: %c", (*wave).events[*event_ix].data);
        runtime_errors += 1;
        return 1;
    }

    v.value.integer = d;

    for (int i = 0; i < (*wave).active_pin_count; i++) {
      vpi_put_value((*(*wave).active_pins[i]).force_data, &v, NULL, vpiNoDelay);
    }
  }

  free(data->user_data);

  return 0;
}


/// Registers a callback to apply the given wave during this cycle
static void bridge_register_wave_event(int wave_ix, int event_ix, int compare, int delay_in_ns) {
  s_cb_data call;
  s_vpi_time time;

  // This will get freed by the callback
  char * user_data = (char *) malloc((sizeof(int) * 3));

  int * d0 = (int*)(&user_data[0]);
  int * d1 = (int*)(&user_data[sizeof(int)]);
  int * d2 = (int*)(&user_data[sizeof(int) * 2]);

  *d0 = wave_ix;
  *d1 = event_ix;
  *d2 = compare;

  time.type = vpiSimTime;
  time.high = (uint32_t)(0);
  time.low  = (uint32_t)(delay_in_ns);

  call.reason    = cbAfterDelay;
  call.cb_rtn    = bridge_apply_wave_event_cb;
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
  time.low  = (uint32_t)(100);  // 100ns chosen as a round number and since the actual
                                // period may not be declared yet

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
  char *opcode, *arg1, *arg2, *arg3, *arg4;
  vpiHandle handle;
  s_vpi_value v;

  while(1) {

    err = client_get(max_msg_len, msg);
    if (err) {
      vpi_printf("ERROR: Failed to receive from Origen!\n");
      return 1;
    }
    if (runtime_errors) {
      return 1;
    }

    opcode = strtok(msg, "^");

    switch(*opcode) {
      // Define pin
      //   0^pin_name^pin_index^drive_wave_ix^capture_wave_ix
      //
      //   0 for the wave indexes means the default, custom waves
      //   must therefore start from index 1
      //
      //   The pin index must be uniquely assigned to the pin by the caller
      //   and must be less than MAX_NUMBER_PINS
      //
      //   0^tdi^12^0^0  
      case '0' :
        arg1 = strtok(NULL, "^");
        arg2 = strtok(NULL, "^");
        arg3 = strtok(NULL, "^");
        arg4 = strtok(NULL, "^");
        //DEBUG("Define Pin: %s, %s, %s, %s\n", arg1, arg2, arg3, arg4);
        bridge_define_pin(arg1, arg2, arg3, arg4);
        break;
      // Set Period
      //   1^100
      case '1' :
        arg1 = strtok(NULL, "^");
        bridge_set_period(arg1);
        break;
      // Drive Pin
      //   2^pin_index^data
      //
      //   2^12^0
      //   2^12^1
      case '2' :
        arg1 = strtok(NULL, "^");
        arg2 = strtok(NULL, "^");
        //DEBUG("Drive Pin: %s, %s\n", arg1, arg2);
        bridge_drive_pin(arg1, arg2);
        break;
      // Cycle
      //   3^number_of_cycles
      //
      //   3^1
      //   3^65535
      case '3' :
        arg1 = strtok(NULL, "^");
        repeat = strtol(arg1, NULL, 10);
        if (repeat) {
          repeat = repeat - 1;
        }
        bridge_cycle();
        return 0;
      // Compare Pin
      //   4^pin_index^data
      //
      //   4^14^0
      //   4^14^1
      case '4' :
        arg1 = strtok(NULL, "^");
        arg2 = strtok(NULL, "^");
        bridge_compare_pin(arg1, arg2);
        break;
      // Don't Care Pin
      //   5^pin_index
      //
      //   5^14
      case '5' :
        arg1 = strtok(NULL, "^");
        bridge_dont_care_pin(arg1);
        break;
      // Define wave
      //   6^wave_index^compare^events
      //
      //   0 for the wave indexes means the default, custom waves
      //   must therefore start from index 1
      //
      //   0 for the compare parameter means it is a drive wave, 1 means it is
      //   for when the pin is in compare mode
      //
      //   Some example events are shown below:
      //
      //   6^1^0^0_D_25_0_50_D_75_0  // Drive at 0ns, off at 25ns, drive at 50ns, off at 75ns
      case '6' :
        arg1 = strtok(NULL, "^");
        arg2 = strtok(NULL, "^");
        arg3 = strtok(NULL, "^");
        //DEBUG("Define Wave: %s, %s, %s\n", arg1, arg2, arg3);
        bridge_define_wave(arg1, arg2, arg3);
        break;
      // Sync-up
      //   7^
      case '7' :
        client_put("OK!\n");
        break;
      // Complete
      //   8^
      case '8' :
        return 0;
      // Error count
      //   Returns the current value of the debug.errors register
      //
      //   9^
      case '9' :
        handle = vpi_handle_by_name("origen_tb.debug.errors", NULL);
        v.format = vpiDecStrVal; // Seems important to set this before get
        vpi_get_value(handle, &v);
        sprintf(msg, "%s\n", v.value.str);
        client_put(msg);
        break;
      // Set Pattern Name
      //   a^atd_ramp_25mhz
      case 'a' :
        handle = vpi_handle_by_name("origen_tb.debug.pattern", NULL);
        arg1 = strtok(NULL, "^");

        v.format = vpiStringVal;
        v.value.str = arg1;
        vpi_put_value(handle, &v, NULL, vpiNoDelay);
        break;
      default :
        vpi_printf("ERROR: Illegal opcode received!\n");
        runtime_errors += 1;
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

  //DEBUG("REPEAT: %d\n", repeat);
  if (repeat) {
    call.cb_rtn    = bridge_cycle_cb;
  } else {
    call.cb_rtn    = bridge_wait_for_msg;
  }

  vpi_free_object(vpi_register_cb(&call));

  bridge_register_wave_events();
}
