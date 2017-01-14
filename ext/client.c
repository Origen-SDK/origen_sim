///
/// This is responsible for abstracting the socket connection to the master
/// Origen process
///
#include "client.h"
#include <errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>

static int sock;

/// Connects to the Origen app's socket
int client_connect(char * socketId) {
  int len;
  struct sockaddr_un remote;

  if (socketId == NULL) {
    printf("ERROR: No socket ID given to the simulator\n");
    return 1;
  }

  if ((sock = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
    printf("ERROR: The simulator failed to create a socket! %s\n", strerror(errno));
    return 1;
  }

  printf("[DEBUG] The socket ID is: %s\n", socketId);
  remote.sun_family = AF_UNIX;
  strcpy(remote.sun_path, socketId);
  len = offsetof(struct sockaddr_un, sun_path) + strlen(remote.sun_path) + 1;

  if (connect(sock, (struct sockaddr *)&remote, len) == -1) {
    printf("ERROR: The simulator failed to connect to Origen's socket! %s\n", strerror(errno));
    return 1;
  }
  return 0;
}


/// Send a message to the master Origen process.
/// NOTE: THE CALLER IS RESPONSIBLE FOR ADDING A \n TERMINATOR TO
///       THE MESSAGE
/// to the data as this function will do it for you.
int client_put(char* data) {
  if(send(sock, data , strlen(data), 0) < 0) {
    return 1;
  }
  return 0;
}


/// Get the next message from the master Origen application process.
/// Blocks until a complete message is received and will be returned in the
/// supplied data array
int client_get(int max_size, char* data) {
  int len;

  while (1) {
    // Have a look at what is available
    len = recv(sock, data, max_size, MSG_PEEK);
    if (len < 0) {
      return 1;
    }

    // See if we have a complete msg yet (by looking for a terminator)
    for (int i = 0; i < len; i++) {
      if (data[i] == '\n') {
        // If so then pull that message out and return it
        recv(sock, data, i + 1, 0);
        data[i] = '\0';
        return 0;
      } 
    }
  }
}
