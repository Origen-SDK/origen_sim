///
/// This implements the bridge between Origen and the simulation, it implements a
/// simple string-based message protocol for communicating between the two domains
///
#include "bridge.h"
#include "client.h"
#include "defines.h"
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <stdarg.h>

#define MAX_NUMBER_PINS 2000
#define MAX_WAVE_EVENTS 50
#define MAX_TRANSACTION_ERRORS 128

typedef struct Pin {
  char *name;
  vpiHandle data;        // A handle to the driver data register
  vpiHandle drive;       // A handle to the driver drive enable register
  vpiHandle force_data;  // A handle to the driver force_data register
  vpiHandle compare;     // A handle to the driver compare enable register
  vpiHandle capture;     // A handle to the driver capture enable register
  int drive_wave;        // Index of the drive wave to be used for this pin
  int compare_wave;      // Index of the compare wave to be used for this pin
  int drive_wave_pos;    // Position of the pin in the drive_wave's active pin array
  int compare_wave_pos;  // Position of the pin in the compare_wave's active pin array
  int index;             // The pin's index in the pins array
  int previous_state;    // Used to keep track of whether the pin was previously driving or comparing
  bool capture_en;       // Used to indicated when compare data should be captured instead of compared
  bool present;          // Set to true if the pin is present in the testbench
} Pin;

typedef struct Event {
  uint64_t time;
  char data;
} Event;

typedef struct Wave {
  Event events[MAX_WAVE_EVENTS];
  Pin *active_pins[MAX_NUMBER_PINS];
  int active_pin_count;
} Wave;

// Used to record a miscompare event that is used by OrigenSim to work out the actual data
// from a failed register read transaction
typedef struct Miscompare {
  char *pin_name;
  unsigned long long cycle;
  int expected;
  int received;
} Miscompare;

static Miscompare miscompares[MAX_TRANSACTION_ERRORS];
static int transaction_error_count = 0;
static bool transaction_open = false;
static int match_loop_error_count = 0;
static bool match_loop_open = false;
static uint64_t period_in_simtime_units;
static unsigned long repeat = 0;
static Pin pins[MAX_NUMBER_PINS];
static int number_of_pins = 0;
// Allocate space for a unique wave for each pin, in reality it will be much less
static Wave drive_waves[MAX_NUMBER_PINS];
static int number_of_drive_waves = 0;
static Wave compare_waves[MAX_NUMBER_PINS];
static int number_of_compare_waves = 0;
static int runtime_errors = 0;
static int log_messages = 0;
static int error_count = 0;
static int max_errors = 100;
static unsigned long long cycle_count = 0;
static bool max_errors_exceeded = false;
static bool max_errors_exceeded_during_transaction = false;

static void set_period(char*);
static void define_pin(char*, char*, char*, char*);
static void define_wave(char*, char*, char*);
static void cycle(void);
static void drive_pin(char*, char*);
static void compare_pin(char*, char*);
static void capture_pin(char*);
static void stop_capture_pin(char*);
static void dont_care_pin(char*);
static void register_wave_events(void);
static void register_wave_event(int, int, int, uint64_t);
static void enable_drive_wave(Pin*);
static void disable_drive_wave(Pin*);
static void enable_compare_wave(Pin*);
static void disable_compare_wave(Pin*);
static void clear_waves_and_pins(void);
static bool is_drive_whole_cycle(Pin*);
static void origen_log(int, const char*, ...);
static void end_simulation(void);
static void on_max_errors_exceeded(void);

static void define_pin(char * name, char * pin_ix, char * drive_wave_ix, char * compare_wave_ix) {
  int index = atoi(pin_ix);
  Pin *pin = &pins[index];
  number_of_pins += 1;

  (*pin).name = malloc(strlen(name) + 1);
  strcpy((*pin).name, name);
  (*pin).index = index;
  (*pin).drive_wave = atoi(drive_wave_ix);
  (*pin).compare_wave = atoi(compare_wave_ix);
  (*pin).previous_state = 0;
  (*pin).capture_en = false;


  char * driver = (char *) malloc(strlen(name) + 16);
  strcpy(driver, ORIGEN_SIM_TESTBENCH_CAT("pins."));
  strcat(driver, name);

  char * data = (char *) malloc(strlen(driver) + 16);
  strcpy(data, driver);
  strcat(data, ".data");
  (*pin).data = vpi_handle_by_name(data, NULL);
  free(data);

  if (!(*pin).data) {
    origen_log(LOG_WARNING, "Your DUT defines pin '%s', however it is not present in the testbench and will be ignored", (*pin).name);
    (*pin).present = false;
  } else {
    (*pin).present = true;
  }

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

  char * capture = (char *) malloc(strlen(driver) + 16);
  strcpy(capture, driver);
  strcat(capture, ".capture");
  (*pin).capture = vpi_handle_by_name(capture, NULL);
  free(capture);

  free(driver);
}


static void define_wave(char * index, char * compare, char * events) {
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
  (*wave).events[i].data = 'T'; // Indicate that there are no more events
  free(myevents);
  (*wave).active_pin_count = 0;
}


static void register_wave_events() {
  for (int i = 0; i < number_of_drive_waves; i++) {

    if (drive_waves[i].active_pin_count) {
      int x = 0;

      while (drive_waves[i].events[x].data != 'T' && x < MAX_WAVE_EVENTS) {
        uint64_t time;

        time = drive_waves[i].events[x].time;

        // TODO: May save some time by calling directly at time 0
        //if (time == 0) {
        //} else {
          register_wave_event(i, x, 0, time);
        //}
        x++;
      }
    }
  }

  for (int i = 0; i < number_of_compare_waves; i++) {

    if (compare_waves[i].active_pin_count) {
      int x = 0;

      while (compare_waves[i].events[x].data != 'T' && x < MAX_WAVE_EVENTS) {
        uint64_t time;

        time = compare_waves[i].events[x].time;

        // TODO: May save some time by calling directly at time 0
        //if (time == 0) {
        //} else {
          register_wave_event(i, x, 1, time);
        //}
        x++;
      }
    }
  }
}


/// Enables the drive condition of the given pin.
/// This is done by adding the pin to the wave's active pin list, if the wave has
/// at least one pin in its list, the necessary callbacks will get triggered on every
/// cycle to implement the required waveform.
static void enable_drive_wave(Pin * pin) {
  Wave *wave = &drive_waves[(*pin).drive_wave];

  (*wave).active_pins[(*wave).active_pin_count] = pin;
  (*pin).drive_wave_pos = (*wave).active_pin_count;
  (*wave).active_pin_count += 1;
}


static void disable_drive_wave(Pin * pin) {
  Wave *wave = &drive_waves[(*pin).drive_wave];

  if ((*wave).active_pin_count == 0) {
    origen_log(LOG_ERROR, "Wanted to disable drive on pin %i, but its drive wave has no active pins!", (*pin).index);
    end_simulation();
  }

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

static void enable_compare_wave(Pin * pin) {
  Wave *wave = &compare_waves[(*pin).compare_wave];

  (*wave).active_pins[(*wave).active_pin_count] = pin;
  (*pin).compare_wave_pos = (*wave).active_pin_count;
  (*wave).active_pin_count += 1;
}

static void disable_compare_wave(Pin * pin) {
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


static void clear_waves_and_pins() {
  for (int i = 0; i < number_of_pins; i++) {
    Pin *pin = &pins[i];
    free((*pin).name);
  }
  number_of_pins = 0;
  number_of_drive_waves = 0;
  number_of_compare_waves = 0;
}


static void set_period(char * p_in_simtime_units_str) {
  uint64_t p = (uint64_t) strtol(p_in_simtime_units_str, NULL, 10);
  period_in_simtime_units = p;
  clear_waves_and_pins();
}


static bool is_drive_whole_cycle(Pin * pin) {
  Wave *wave = &drive_waves[(*pin).drive_wave];

  // If drive wave only has one event
  if ((*wave).events[1].data == 'T') {
    // Return true if the single event specifies drive for the whole cycle
    return (*wave).events[0].data == 'D' &&
           (*wave).events[0].time == 0;
  } else {
    return false;
  }
}


/// Immediately drives the given pin to the given value
static void drive_pin(char * index, char * val) {
  Pin *pin = &pins[atoi(index)];
  s_vpi_value v = {vpiIntVal, {0}};

  if ((*pin).present) {
    // Apply the data value to the pin's driver
    v.value.integer = (val[0] - '0');
    vpi_put_value((*pin).data, &v, NULL, vpiNoDelay);
    // Make sure not comparing
    v.value.integer = 0;
    vpi_put_value((*pin).compare, &v, NULL, vpiNoDelay);

    // Register it as actively driving with it's wave
    
    // If it is already driving the wave will already be setup
    if ((*pin).previous_state != 1) {
      // If the drive is for the whole cycle, then we can enable it here
      // and don't need a callback
      if (is_drive_whole_cycle(pin)) {
        v.value.integer = 1;
        vpi_put_value((*pin).drive, &v, NULL, vpiNoDelay);
      } else {
        enable_drive_wave(pin);
      }

      if ((*pin).previous_state == 2) {
        disable_compare_wave(pin);
      }
      (*pin).previous_state = 1;
    }
  }
}


/// Immediately sets the given pin to compare against the given value
static void compare_pin(char * index, char * val) {
  Pin *pin = &pins[atoi(index)];
  s_vpi_value v = {vpiIntVal, {0}};

  if ((*pin).present) {
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
      enable_compare_wave(pin);
      if ((*pin).previous_state == 1) {
        if (!is_drive_whole_cycle(pin)) {
          disable_drive_wave(pin);
        }
      }
      (*pin).previous_state = 2;
    }
  }
}


/// Immediately sets the given pin to capture by registering it for compare
/// but with its capture flag set
static void capture_pin(char * index) {
  Pin *pin = &pins[atoi(index)];
  (*pin).capture_en = true;
  compare_pin(index, "0");
}


/// Immediately sets the given pin to stop capture by clearing its capture flag
static void stop_capture_pin(char * index) {
  Pin *pin = &pins[atoi(index)];
  (*pin).capture_en = false;
}


/// Immediately sets the given pin to don't compare
static void dont_care_pin(char * index) {
  Pin *pin = &pins[atoi(index)];
  s_vpi_value v = {vpiIntVal, {0}};

  if ((*pin).present) {
    // Disable drive and compare on the pin's driver
    v.value.integer = 0;
    vpi_put_value((*pin).drive, &v, NULL, vpiNoDelay);
    vpi_put_value((*pin).compare, &v, NULL, vpiNoDelay);

    if ((*pin).previous_state != 0) {
      if ((*pin).previous_state == 1) {
        if (!is_drive_whole_cycle(pin)) {
          disable_drive_wave(pin);
        }
      }
      if ((*pin).previous_state == 2) {
        disable_compare_wave(pin);
      }
      (*pin).previous_state = 0;
    }
  }
}


/// Callback handler to implement the events registered by register_wave_event
PLI_INT32 apply_wave_event_cb(p_cb_data data) {
  s_vpi_value v = {vpiIntVal, {0}};
  s_vpi_value v2 = {vpiIntVal, {0}};

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
        origen_log(LOG_ERROR, "Unknown compare event: %c", (*wave).events[*event_ix].data);
        runtime_errors += 1;
        end_simulation();
        return 1;
    }

    v.value.integer = d;
    for (int i = 0; i < (*wave).active_pin_count; i++) {
      if ((*(*wave).active_pins[i]).capture_en) {
        vpi_put_value((*(*wave).active_pins[i]).capture, &v, NULL, vpiNoDelay);
      } else {
        vpi_put_value((*(*wave).active_pins[i]).compare, &v, NULL, vpiNoDelay);
      }
    }


  } else {

    wave = &drive_waves[*wave_ix];

    //vpi_printf("[DEBUG] Apply drive wave %i, event %i, data %c\n", *wave_ix, *event_ix, (*wave).events[*event_ix].data);

    int d;
    int on;
    switch((*wave).events[*event_ix].data) {
      case '0' :
        d = 1;
        on = 1;
        break;
      case '1' :
        d = 2;
        on = 1;
        break;
      case 'D' :
        d = 0;
        on = 1;
        break;
      case 'X' :
        d = 0;
        on = 0;
        break;
      default :
        origen_log(LOG_ERROR, "Unknown drive event: %c\n", (*wave).events[*event_ix].data);
        runtime_errors += 1;
        end_simulation();
        return 1;
    }

    v.value.integer = d;
    v2.value.integer = on;
    if (on) {
      for (int i = 0; i < (*wave).active_pin_count; i++) {
        vpi_put_value((*(*wave).active_pins[i]).force_data, &v, NULL, vpiNoDelay);
        vpi_put_value((*(*wave).active_pins[i]).drive, &v2, NULL, vpiNoDelay);
      }
    } else {
      for (int i = 0; i < (*wave).active_pin_count; i++) {
        vpi_put_value((*(*wave).active_pins[i]).drive, &v2, NULL, vpiNoDelay);
      }
    }
  }

  free(data->user_data);

  return 0;
}


/// Registers a callback to apply the given wave during this cycle
static void register_wave_event(int wave_ix, int event_ix, int compare, uint64_t delay_in_simtime_units) {
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

  time.high = (uint32_t)(delay_in_simtime_units >> 32);
  time.low  = (uint32_t)(delay_in_simtime_units);

  call.reason    = cbAfterDelay;
  call.cb_rtn    = apply_wave_event_cb;
  call.obj       = 0;
  call.time      = &time;
  call.value     = 0;
  call.user_data = user_data;

  vpi_free_object(vpi_register_cb(&call));
}


/// Entry point to the bridge_wait_for_msg loop
PLI_INT32 bridge_init() {
  client_put("READY!\n");
  return bridge_wait_for_msg(NULL);
}


/// Send output to the Origen log, this will be automatically timestamped to the simulation and
/// sprintf type arguments can be supplied when calling:
///
///    origen_log(LOG_ERROR, "Wanted to disable drive on pin %i, but its drive wave has no active pins!", (*pin).index);
///    origen_log(LOG_INFO, "Something to tell you about");
static void origen_log(int type, const char * fmt, ...) {
  s_vpi_time now;
  int max_msg_len = 2048;
  char msg[max_msg_len];
  va_list aptr;

  now.type = vpiSimTime;
  vpi_get_time(0, &now);

  va_start(aptr, fmt);
  vsprintf(msg, fmt, aptr);
  va_end(aptr);

  vpi_printf("!%d![%u,%u] %s\n", type, now.high, now.low, msg);
};


/// Waits and responds to instructions from Origen (to set pin states).
/// When Origen requests a cycle, time will be advanced and this func will be called again.
PLI_INT32 bridge_wait_for_msg(p_cb_data data) {
  UNUSED(data);
  int max_msg_len = 1024;
  char msg[max_msg_len];
  char comment[128];
  int err;
  int timescale;
  int type;
  char *opcode, *arg1, *arg2, *arg3, *arg4;
  vpiHandle handle;
  s_vpi_value v;

  while(1) {

    err = client_get(max_msg_len, msg);
    if (err) {
      // Don't send to the Origen log since Origen may not be there
      vpi_printf("ERROR: Failed to receive from Origen!\n");
      end_simulation();
      return 1;
    }
    if (runtime_errors) {
      end_simulation();
      return 1;
    }

    if (log_messages) {
      vpi_printf("[MESSAGE] %s\n", msg);
    }

    // Keep a copy of the original message, helpful for debugging
    char* orig_msg = calloc(strlen(msg)+1, sizeof(char));
    strcpy(orig_msg, msg);

    opcode = strtok(msg, "^");

    if (!max_errors_exceeded || (max_errors_exceeded && (
      // When max_errors_exceeded, only continue to process the following opcodes.
      // These are the ones required to enable a controlled shutdown driven by the main Origen process
      // and also any that return data to Origen so that the main process does not get blocked:
      //     Sync-up           End Simulation    Peek              Flush               Log
            *opcode == '7' || *opcode == '8' || *opcode == '9' || *opcode == 'j' || *opcode == 'k' ||
      //     Get version      Get timescale     Read reg trans   Get cycle count
            *opcode == 'i' || *opcode == 'l' || *opcode == 'n' || *opcode == 'o'
      ))) {
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
          define_pin(arg1, arg2, arg3, arg4);
          break;
        // Set Period
        //   1^100000
        case '1' :
          arg1 = strtok(NULL, "^");
          set_period(arg1);
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
          drive_pin(arg1, arg2);
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
          cycle();
          return 0;
        // Compare Pin
        //   4^pin_index^data
        //
        //   4^14^0
        //   4^14^1
        case '4' :
          arg1 = strtok(NULL, "^");
          arg2 = strtok(NULL, "^");
          compare_pin(arg1, arg2);
          break;
        // Don't Care Pin
        //   5^pin_index
        //
        //   5^14
        case '5' :
          arg1 = strtok(NULL, "^");
          dont_care_pin(arg1);
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
          define_wave(arg1, arg2, arg3);
          break;
        // Sync-up
        //   7^
        case '7' :
          client_put("OK!\n");
          break;
        // Complete
        //   8^
        case '8' :
          end_simulation();
          return 0;
        // Peek
        //   Returns the current value of the given net, the 2nd argument specifies whether to
        //   return an integer or a float/real value
        //
        //   9^origen.debug.errors^i
        //   9^origen.dut.my_real_val^f
        case '9' :
          arg1 = strtok(NULL, "^");
          arg2 = strtok(NULL, "^");
          handle = vpi_handle_by_name(arg1, NULL);
          if (handle) {
            if (*arg2 == 'i') {
              v.format = vpiBinStrVal;
              vpi_get_value(handle, &v);
              sprintf(msg, "%s\n", v.value.str);
            } else {
              v.format = vpiRealVal;
              vpi_get_value(handle, &v);
              sprintf(msg, "%f\n", v.value.real);
            }
            client_put(msg);
          } else {
            client_put("FAIL\n");
          }
          break;
        // Set Pattern Name
        //   a^atd_ramp_25mhz
        case 'a' :
          handle = vpi_handle_by_name(ORIGEN_SIM_TESTBENCH_CAT("debug.pattern"), NULL);
          arg1 = strtok(NULL, "^");

          v.format = vpiStringVal;
          v.value.str = arg1;
          vpi_put_value(handle, &v, NULL, vpiNoDelay);
          break;
        // Poke
        //   Sets the given value on the given net, the number should be given
        //   as a decimal string, an integer or a float, and the 2nd argument specifies
        //   which has been given
        //
        //   b^origen.debug.errors^i^15
        //   b^origen.dut.my_real_val^f^1.12
        case 'b' :
          arg1 = strtok(NULL, "^");
          arg2 = strtok(NULL, "^");
          arg3 = strtok(NULL, "^");
          handle = vpi_handle_by_name(arg1, NULL);
          if (handle) {
            if (*arg2 == 'i') {
              v.format = vpiDecStrVal;
              v.value.str = arg3;
            } else {
              v.format = vpiRealVal;
              v.value.real = strtof(arg3, NULL);
            }
            vpi_put_value(handle, &v, NULL, vpiNoDelay);
          }
          break;
        // Set Comment
        //   c^0^Some comment about the pattern
        case 'c' :
          arg1 = strtok(NULL, "^");
          arg2 = strtok(NULL, "^");

          strcpy(comment, ORIGEN_SIM_TESTBENCH_CAT("debug.comments"));
          strcat(comment, arg1);

          handle = vpi_handle_by_name(comment, NULL);

          v.format = vpiStringVal;
          v.value.str = arg2;
          vpi_put_value(handle, &v, NULL, vpiNoDelay);
          break;
        // Log all messages
        //   d^1  Turn logging on
        //   d^0  Turn logging off
        case 'd' :
          arg1 = strtok(NULL, "^");
          log_messages = atoi(arg1);
          break;
        // Capture Pin
        //   e^pin_index
        //
        //   e^14
        case 'e' :
          arg1 = strtok(NULL, "^");
          capture_pin(arg1);
          break;
        // Sync enable
        case 'f' :
          handle = vpi_handle_by_name(ORIGEN_SIM_TESTBENCH_CAT("pins.sync"), NULL);
          v.format = vpiDecStrVal;
          v.value.str = "1";
          vpi_put_value(handle, &v, NULL, vpiNoDelay);
          break;
        // Sync disable
        case 'g' :
          handle = vpi_handle_by_name(ORIGEN_SIM_TESTBENCH_CAT("pins.sync"), NULL);
          v.format = vpiDecStrVal;
          v.value.str = "0";
          vpi_put_value(handle, &v, NULL, vpiNoDelay);
          break;
        // Stop Capture Pin
        //   h^pin_index
        //
        //   h^14
        case 'h' :
          arg1 = strtok(NULL, "^");
          stop_capture_pin(arg1);
          break;
        // Get version, returns the version of OrigenSim the DUT object was compiled with
        //   i^
        case 'i' :
          client_put(ORIGEN_SIM_VERSION"\n");
          break;
        // Flush
        case 'j' :
          vpi_flush();
          break;
        // Log message
        //   k^2^A message to output to the console/log
        case 'k' :
          arg1 = strtok(NULL, "^");
          arg2 = strtok(NULL, "^");
          type = atoi(arg1);
          origen_log(type, arg2); 
          break;
        // Get timescale, returns a number that maps as follows:
        //      -15 - fs
        //      -14 - 10fs
        //      -13 - 100fs
        //      -12 - ps
        //      -11 - 10ps
        //      -10 - 100ps
        //      -9  - ns
        //      -8  - 10ns
        //      -7  - 100ns
        //      -6  - us
        //      -5  - 10us
        //      -4  - 100us
        //      -3  - ms
        //      -2  - 10ms
        //      -1  - 100ms
        //       0   - s
        //       1   - 10s
        //       2   - 100s
        //   l^
        case 'l' :
          timescale = vpi_get(vpiTimeUnit, 0);
          sprintf(msg, "%d\n", timescale);
          client_put(msg);
          break;
        // Set max_errors
        //   m^10
        case 'm' :
          arg1 = strtok(NULL, "^");
          max_errors = atoi(arg1);
          break;
        // Read reg transaction
        //   n^1   - Start transaction
        //   n^0   - Stop transaction
        case 'n' :
          arg1 = strtok(NULL, "^");
          
          if (*arg1 == '1') {
            transaction_error_count = 0;
            transaction_open = true;
          } else {
            // Send Origen the error data
            sprintf(msg, "%d,%d\n", transaction_error_count, MAX_TRANSACTION_ERRORS);
            client_put(msg);
            for (int i = 0; i < transaction_error_count; i++) {
              Miscompare *m = &miscompares[i];

              sprintf(msg, "%s,%llu,%d,%d\n", (*m).pin_name, (*m).cycle, (*m).expected, (*m).received);
              client_put(msg);

              free((*m).pin_name);
            }
            transaction_open = false;
            if (max_errors_exceeded_during_transaction) {
              on_max_errors_exceeded();
            }
          }
          break;
        // Get cycle count
        //   o^
        case 'o' :
          sprintf(msg, "%llu\n", cycle_count);
          client_put(msg);
          break;
        // Set cycle count
        //   p^100
        case 'p' :
          arg1 = strtok(NULL, "^");
          cycle_count = atoll(arg1);
          break;
        // Match loop
        //   q^1    - Start match loop
        //   q^0    - Stop match loop
        case 'q' :
          arg1 = strtok(NULL, "^");
          
          if (*arg1 == '1') {
            match_loop_error_count = 0;
            match_loop_open = true;
          } else {
            match_loop_open = false;
          }
          break;
        // Force
        //   Forces the given value on the given net, the number should be given
        //   as a decimal string, an integer or a float, and the 2nd argument specifies
        //   which has been given
        //
        //   r^origen.dut.some.net^i^1^
        //   r^origen.dut.some.net^f^1.25
        case 'r' :
          arg1 = strtok(NULL, "^");
          arg2 = strtok(NULL, "^");
          arg3 = strtok(NULL, "^");
          handle = vpi_handle_by_name(arg1, NULL);
          if (handle) {
            if (*arg2 == 'i') {
              v.format = vpiDecStrVal;
              v.value.str = arg3;
            } else {
              v.format = vpiRealVal;
              v.value.real = strtof(arg3, NULL);
            }
            vpi_put_value(handle, &v, NULL, vpiForceFlag);
          }
          break;
        // Release
        //   Releases an existing force on the given net
        //
        //   s^origen.dut.some.net
        //   s^origen.dut.some.net
        case 's' :
          arg1 = strtok(NULL, "^");
          handle = vpi_handle_by_name(arg1, NULL);
          if (handle) {
            vpi_put_value(handle, &v, NULL, vpiReleaseFlag);
          }
          break;
        default :
          origen_log(LOG_ERROR, "Illegal message received from Origen: %s", orig_msg);
          runtime_errors += 1;
          end_simulation();
          return 1;
      }
    } else {
      // Simulation has been aborted but not told to end yet by Origen
      repeat = 0;
      set_period("1");
      cycle();
    }
    free(orig_msg);
  }
}


static void end_simulation() {
  vpiHandle handle;
  s_vpi_value v;

  // Setting this node will cause the testbench to call $finish
  handle = vpi_handle_by_name(ORIGEN_SIM_TESTBENCH_CAT("finish"), NULL);
  v.format = vpiDecStrVal;
  v.value.str = "1";
  vpi_put_value(handle, &v, NULL, vpiNoDelay);
  // Corner case during testing, the timeset may not have been set yet
  set_period("1");
  // Do a cycle so that the simulation sees the edge on origen.finish
  cycle();
}


PLI_INT32 cycle_cb(p_cb_data data) {
  UNUSED(data);
  repeat = repeat - 1;
  cycle();
  return 0;
}


/// Registers a callback after a cycle period, the main server loop should unblock
/// after calling this to allow the simulation to proceed for a cycle
static void cycle() {
  s_cb_data call;
  s_vpi_time time;

  time.type = vpiSimTime;
  time.high = (uint32_t)(period_in_simtime_units >> 32);
  time.low  = (uint32_t)(period_in_simtime_units);

  cycle_count++;

  call.reason    = cbAfterDelay;
  call.obj       = 0;
  call.time      = &time;
  call.value     = 0;
  call.user_data = 0;

  //DEBUG("REPEAT: %d\n", repeat);
  if (repeat) {
    call.cb_rtn    = cycle_cb;
  } else {
    call.cb_rtn    = bridge_wait_for_msg;
  }

  vpi_free_object(vpi_register_cb(&call));

  register_wave_events();
}

static void on_max_errors_exceeded() {
  // This will cause the simulation to stop processing messages from Origen
  max_errors_exceeded = true;
  // And this let's the Origen process know that we have stopped processing
  origen_log(LOG_ERROR, "!MAX_ERROR_ABORT!");
}

/// Called every time a miscompare event occurs, 3 args will be passed in:
/// the pin name, expected data, actual data
PLI_INT32 bridge_on_miscompare(PLI_BYTE8 * user_dat) {
  char *pin_name;
  int expected;
  int received;
  s_vpi_value val;
  vpiHandle handle;

  if (match_loop_open) {
    match_loop_error_count++;

    handle = vpi_handle_by_name(ORIGEN_SIM_TESTBENCH_CAT("debug.match_errors"), NULL);
    val.format = vpiIntVal;
    val.value.integer = match_loop_error_count;
    vpi_put_value(handle, &val, NULL, vpiNoDelay);

  } else {
    vpiHandle callh = vpi_handle(vpiSysTfCall, 0);
    vpiHandle argv = vpi_iterate(vpiArgument, callh);
    vpiHandle arg;

    arg = vpi_scan(argv);
    val.format = vpiStringVal;
    vpi_get_value(arg, &val);
    pin_name = val.value.str;

    arg = vpi_scan(argv);
    val.format = vpiIntVal;
    vpi_get_value(arg, &val);
    expected = val.value.integer;

    arg = vpi_scan(argv);
    val.format = vpiIntVal;
    vpi_get_value(arg, &val);
    received = val.value.integer;

    vpi_free_object(argv);

    if (received) {
      origen_log(LOG_ERROR, "Miscompare on pin %s, expected %d received %d", pin_name, expected, received);
    } else {
      origen_log(LOG_ERROR, "Miscompare on pin %s, expected %d received X or Z", pin_name, expected);
    }

    error_count++;

    handle = vpi_handle_by_name(ORIGEN_SIM_TESTBENCH_CAT("debug.errors"), NULL);
    val.format = vpiIntVal;
    val.value.integer = error_count;
    vpi_put_value(handle, &val, NULL, vpiNoDelay);

    if (error_count > max_errors) {
      // If a transaction is currently open hold off aborting until after that has completed
      // to enable a proper error message to be generated for it
      if (transaction_open) {
        max_errors_exceeded_during_transaction = true;
      } else {
        on_max_errors_exceeded();
      }
    }

    // Store all errors during a transaction
    if (transaction_open) {
      if (transaction_error_count < MAX_TRANSACTION_ERRORS) {
        Miscompare *miscompare = &miscompares[transaction_error_count];

        (*miscompare).pin_name = malloc(strlen(pin_name) + 1);
        strcpy((*miscompare).pin_name, pin_name);
        (*miscompare).cycle = cycle_count;
        (*miscompare).expected = expected;
        if (received) {
          (*miscompare).received = received;
        } else {
          (*miscompare).received = -1;
        }
      }
      transaction_error_count++;
    }
  }
  return 0;
}

/// Defines which functions are callable from Verilog as system tasks
void bridge_register_system_tasks() {
  s_vpi_systf_data tf_data;

  tf_data.type = vpiSysTask;
  tf_data.tfname = "$bridge_on_miscompare";
  tf_data.calltf = bridge_on_miscompare;
  tf_data.compiletf = 0;
  vpi_register_systf(&tf_data);
}
