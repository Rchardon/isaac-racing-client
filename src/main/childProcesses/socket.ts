/* eslint-disable import/no-unused-modules */

// Child process that runs a socket server
// We forward along socket messages to the parent process,
// which in turn sends them to the renderer process
// All messages to the parent must be in the form of "commandName rest of the data"

import net from "net";
import log from "../../common/log";
import { unpackSocketMsg } from "../../common/util";
import { processExit } from "./subroutines";

const PORT = 9112; // Arbitrarily chosen to not conflict with common IANA ports

const sockets: net.Socket[] = [];

// We use a different error message here than in the other child processes
init();

function init() {
  process.on("uncaughtException", onUncaughtException);
  process.on("message", onMessage);

  const server = net.createServer(connectionListener);
  server.on("error", (err) => {
    throw err;
  });
  server.listen(PORT, () => {
    log.info(`Server started on port ${PORT}.`);
  });
}

function onUncaughtException(err: Error) {
  if (process.send !== undefined) {
    // We forward all errors back to the parent process like in the other child processes
    // But we use a prefix of "error" here instead of "error:"
    process.send(`error ${err} | ${new Error().stack}`, processExit());
  }
}

function onMessage(message: string) {
  switch (message) {
    case "exit": {
      // The child will stay alive even if the parent has closed,
      // so we depend on the parent telling us when to die
      process.exit();
      break;
    }

    default: {
      for (const socket of sockets) {
        // The Lua socket library expects all messages to be terminated by a newline
        socket.write(`${message}\n`);
      }
      break;
    }
  }
}

function connectionListener(socket: net.Socket) {
  if (process.send === undefined) {
    throw new Error("process.send() does not exist.");
  }

  // Keep track of the newly connected client
  sockets.push(socket);

  const clientAddress = `${socket.remoteAddress}:${socket.remotePort}`;
  process.send(
    `info Client "${clientAddress}" has connected to the socket server. (${sockets.length} total clients)`,
  );
  process.send("connected");

  socket.on("data", socketData);

  socket.on("close", () => {
    socketClose(socket, clientAddress);
  });

  socket.on("error", (err) => {
    socketError(err, clientAddress);
  });
}

function socketData(buffer: Buffer) {
  if (process.send === undefined) {
    throw new Error("process.send() does not exist.");
  }

  const rawData = buffer.toString();
  const command = unpackSocketMsg(rawData)[0];

  // The client will send a ping on every frame as a means of checking whether or not the socket
  // is closed
  // These can be ignored
  if (command === "ping") {
    return;
  }

  // Forward all messages received from the client to the parent process
  process.send(rawData);
}

function socketClose(socket: net.Socket, clientAddress: string) {
  if (process.send === undefined) {
    throw new Error("process.send() does not exist.");
  }

  // Remove it from our list of sockets
  const index = sockets.indexOf(socket);
  if (index > -1) {
    sockets.splice(index, 1);
  }

  process.send(
    `info Client "${clientAddress} has disconnected from the socket server. (${sockets.length} total clients)`,
  );

  if (sockets.length === 0) {
    process.send("disconnected");
  }
}

function socketError(err: Error, clientAddress: string) {
  if (process.send === undefined) {
    throw new Error("process.send() does not exist.");
  }

  process.send(
    `error The socket server got an error for client "${clientAddress}": ${err}`,
  );
}
