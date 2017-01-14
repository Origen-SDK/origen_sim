#ifndef CLIENT_H
#define CLIENT_H

#include "common.h"

int client_connect(char *);
int client_get(int, char*);
int client_put(char*);

#endif
