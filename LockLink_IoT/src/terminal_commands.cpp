#include "terminal_commands.h"
#include "config.h"
#include "local_network.h"
#include "matter_release.h"
#include <IPAddress.h>

TerminalReply terminalCommand(String command, ReleaseOutput& output, UnlockAuth& auth) {
  TerminalReply reply;
  command.trim();
  command.toUpperCase();
  reply.commissioned = matter_release::commissioned();
  if (command.isEmpty()) return reply;
  if (command == "HELP") {
    reply.output = "HELP   Commands\nSTATUS Device state\nPAIR   Matter setup code\nRESET MATTER   USB only; erases homes and Wi-Fi.";
  } else if (command == "STATUS") {
    const auto network = local_network::snapshot();
    reply.output = String("Wi-Fi: ") + (network.ready() ? IPAddress(network.ipv4).toString() : "offline") +
        "\nMatter: " + (reply.commissioned ? "paired" : "not paired") +
        "\nOutput: " + (config::relayEnabled ? "relay" : "LED") +
        "; armed: " + (!config::relayEnabled || auth.ready() ? "yes" : "no") +
        "\nRelease: " + (output.active() ? "active" : "inactive") +
        "\n" + matter_release::identity();
  } else if (command == "PAIR") {
    reply.pairingCode = matter_release::preparePairing(reply.output, reply.pairingQrPayload);
    // Commissioning may have completed while the request acquired the stack lock.
    reply.commissioned = matter_release::commissioned();
    if (reply.commissioned) {
      reply.pairingCode = "";
      reply.pairingQrPayload = "";
      reply.output = "Already paired. Get a sharing code from the connected home app.";
    }
    reply.ok = reply.commissioned || !reply.pairingCode.isEmpty();
  } else {
    reply.ok = false;
    reply.output = command == "RESET MATTER"
        ? "USB only. Erases homes and Wi-Fi."
        : "Unknown command. Type HELP.";
  }
  return reply;
}
