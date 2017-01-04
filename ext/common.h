#ifndef COMMON_H
#define COMMON_H

#include <stddef.h>
#include "vpi_user.h"
#define UNUSED(x) (void)(x)

#define ENABLE_DEBUG

#ifdef ENABLE_DEBUG
/* #define DEBUG(fmt, args...) fprintf(stderr, "DEBUG: %s:%d:%s(): " fmt, \
    __FILE__, __LINE__, __func__, ##args) */
 #define DEBUG(fmt, args...) fprintf(stderr, "[DEBUG] " fmt, ##args)
#else
 #define DEBUG(fmt, args...) /* Don't do anything in release builds */
#endif

#endif
