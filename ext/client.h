#ifndef CLIENT_H
#define CLIENT_H

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include "common.h"

int client_connect(char *);
int client_get(int, char*);
int client_put(char*);

#endif
