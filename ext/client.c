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
