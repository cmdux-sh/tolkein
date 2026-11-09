extension AntigravityStatusProbe {
    static func cliEndpoints(ports: [Int]) -> [AntigravityConnectionEndpoint] {
        ports.flatMap { port in
            self.localProbeSchemes.map { scheme in
                AntigravityConnectionEndpoint(
                    scheme: scheme,
                    port: port,
                    csrfToken: "",
                    source: .cliHTTPS)
            }
        }
    }

    static var localProbeSchemes: [String] {
        ["https"]
    }
}
