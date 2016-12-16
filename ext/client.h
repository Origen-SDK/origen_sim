#ifndef CLIENT_H
#define CLIENT_H

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include "common.h"

int origen_connect(char *);
int origen_get(int, char*);
int origen_put(char*);

#endif
