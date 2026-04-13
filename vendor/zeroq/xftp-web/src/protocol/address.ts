import {base64urlEncode} from "./description.js"

export interface XFTPServer {
  keyHash: Uint8Array
  host: string
  port: string
}

function base64urlDecode(s: string): Uint8Array {
  let b64 = s.replace(/-/g, '+').replace(/_/g, '/')
  while (b64.length % 4 !== 0) b64 += '='
  const bin = atob(b64)
  const bytes = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
  return bytes
}

export function parseXFTPServer(address: string): XFTPServer {
  const m = address.match(/^xftp:\/\/([A-Za-z0-9_-]+={0,2})@(.+)$/)
  if (!m) throw new Error("parseXFTPServer: invalid address format")
  const keyHash = base64urlDecode(m[1])
  if (keyHash.length !== 32) throw new Error("parseXFTPServer: keyHash must be 32 bytes")
  const hostPart = m[2]
  const firstHost = hostPart.split(',')[0]
  return {keyHash, ...parseHostPort(firstHost)}
}

function parseHostPort(firstHost: string): Pick<XFTPServer, "host" | "port"> {
  if (firstHost.length === 0) throw new Error("parseXFTPServer: missing host")
  if (firstHost.startsWith('[')) {
    const bracketEnd = firstHost.indexOf(']')
    if (bracketEnd < 0) throw new Error("parseXFTPServer: invalid bracketed host")
    const host = firstHost.substring(0, bracketEnd + 1)
    const rest = firstHost.substring(bracketEnd + 1)
    if (rest.length === 0) return {host, port: "443"}
    if (!rest.startsWith(':')) throw new Error("parseXFTPServer: invalid bracketed host")
    const port = rest.substring(1)
    if (port.length === 0) throw new Error("parseXFTPServer: missing port")
    return {host, port}
  }
  const colonIdx = firstHost.lastIndexOf(':')
  let host: string
  let port: string
  if (colonIdx > 0) {
    host = firstHost.substring(0, colonIdx)
    port = firstHost.substring(colonIdx + 1)
  } else {
    host = firstHost
    port = "443"
  }
  return {host, port}
}

export function formatXFTPServer(srv: XFTPServer): string {
  return "xftp://" + base64urlEncode(srv.keyHash) + "@" + srv.host + ":" + srv.port
}

export function getDescriptionServers(fd: {chunks: {replicas: {server: string}[]}[]}): XFTPServer[] {
  const seen = new Set<string>()
  const servers: XFTPServer[] = []
  for (const chunk of fd.chunks) {
    for (const replica of chunk.replicas) {
      if (!seen.has(replica.server)) {
        seen.add(replica.server)
        servers.push(parseXFTPServer(replica.server))
      }
    }
  }
  return servers
}

export function serverOrigin(server: XFTPServer): string {
  return server.port === "443" ? `https://${server.host}` : `https://${server.host}:${server.port}`
}
