#ifndef COMMON_H
#define COMMON_H

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include "vpi_user.h"
#include <stdbool.h>
#include <stdint.h>
#define UNUSED(x) (void)(x)

#define ENABLE_DEBUG

/// Prepends the testbench name to the signal.
/// e.g.: TESTBENCH_CAT(pins) => TESTBENCH_NAME.pins => origen.pins
#define ORIGEN_SIM_TESTBENCH_CAT(signal) ORIGEN_SIM_TESTBENCH_NAME "." signal

#ifdef ENABLE_DEBUG
/* #define DEBUG(fmt, args...) fprintf(stderr, "DEBUG: %s:%d:%s(): " fmt, \
    __FILE__, __LINE__, __func__, ##args) */
 #define DEBUG(fmt, args...) fprintf(stderr, "[DEBUG] " fmt, ##args)
#else
 #define DEBUG(fmt, args...) /* Don't do anything in release builds */
#endif

#endif
