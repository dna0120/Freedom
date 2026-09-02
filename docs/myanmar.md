# Case study: WireGuard handshake failed in Myanmar, AmneziaWG did not

This is a **diagnostic write-up**, not a copy-paste bypass pack. Parameters that work this week go stale; the decision process does not.

## Environment

- **Client location:** Myanmar
- **Server:** existing WireGuard endpoint that already worked for other clients on other networks
- **Symptom unique to this network:** UDP reachability looked fine; the tunnel did not

## What was already true

Other machines could connect to the same `wg0` interface. So this was not “the VPS is down”, “the port is closed on the firewall”, or “the keys are wrong”.

A TCP/UDP port probe (`nc -vzu <ip> <port>`) against the WireGuard listen port **succeeded**. That is the trap. An open UDP port is not a completed WireGuard handshake. The ISP can still classify and drop the handshake packets after the datagrams have already reached the host.

## What failed

Plain WireGuard: client sat on keepalive / handshake retry. Traffic never came up.

That pattern — **UDP probe OK, handshake dead, other networks fine** — is the fingerprint of DPI on the WireGuard protocol itself, not a generic UDP block.

## What we changed

On the **same VPS**, AmneziaWG was added as a second interface (`wg1`) so the working `wg0` peers were left alone. No rebuild, no migration of existing clients.

AmneziaWG is obfuscated WireGuard: the datagram no longer looks like a stock handshake. After switching the Myanmar client to that interface, the tunnel came up.

We did **not** conclude “AmneziaWG always beats every ISP”. We concluded that **on this network, at that time**, protocol camouflage was the missing layer, not another listen port and not a commercial app profile.

## How to tell you are in the same case

Work through this order before changing software:

1. Other clients on other ISPs still connect to the same server → server and keys are probably fine.
2. UDP probe to the listen port succeeds from the failing network → it is not a blind UDP drop.
3. Handshake / keepalive never completes → inspect DPI, not DNS and not “try another NordVPN server”.
4. Only then try an obfuscated WireGuard variant (AmneziaWG) or a TCP/TLS camouflage stack (VLESS+REALITY). Do not stack every protocol on day one.

If step 2 **fails** (UDP never arrives), you have a different problem: UDP blocking. Then QUIC/Hysteria2 or a TCP stack is the first experiment, not AmneziaWG.

## What this installer is for

[Freedom](https://github.com/dna0120/Freedom) installs AmneziaWG, Xray (VLESS+REALITY, optional CDN), and Hysteria2 on one VPS so you can pick the stack that matches the failure mode above — without running three unrelated installers.

## Paid work

The installer is free. Diagnosis against a live ISP, hardening, and keeping a node alive when DPI changes is not.

- Email: [dat.tranthanh0919@gmail.com](mailto:dat.tranthanh0919@gmail.com)
- Upwork: [Tran T. — Network Engineer | VPN Obfuscation & Infra Specialist](https://www.upwork.com/freelancers/~010476dc2bd9f8d912)
