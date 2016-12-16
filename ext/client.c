#include "client.h"

static int sock;

/// Connects to the Origen app's socket
int origen_connect(char * socketId) {
  int len;
  struct sockaddr_un remote;

  if ((sock = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
    return 1;
  }

  remote.sun_family = AF_UNIX;
  strcpy(remote.sun_path, socketId);
  len = strlen(remote.sun_path) + sizeof(remote.sun_family);
  if (connect(sock, (struct sockaddr *)&remote, len) == -1) {
    return 1;
  }

  //while(printf("> "), fgets(str, 100, stdin), !feof(stdin)) {
  //  if (send(sock, str, strlen(str), 0) == -1) {
  //      perror("send");
  //      exit(1);
  //  }

  //  if ((t=recv(sock, str, 100, 0)) > 0) {
  //      str[t] = '\0';
  //      printf("echo> %s", str);
  //  } else {
  //      if (t < 0) perror("recv");
  //      else printf("Server closed connection\n");
  //      exit(1);
  //  }
  //}

  return 0;
}


/// Get the next message from the master Origen application process.
/// Blocks until a complete message is received and will be returned in the
/// supplied data array
int origen_get(int max_size, char* data) {
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
