// Copyright 2016-2021 Cisco Systems Inc
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation

class MetricsEngine {

    private let bufferLimit = 50
    private let client: MetricsClient
    private var buffer = MetricsBuffer()
    private lazy var timer: Timer = Timer(timeInterval: 30, target: self, selector: #selector(flush), userInfo: nil, repeats: true)
    let authenticator: Authenticator
    var iceMediaLines: [ClientEventMediaLine]?

    init(authenticator: Authenticator, service: DeviceService) {
        self.authenticator = authenticator
        self.client = MetricsClient(authenticator: authenticator, service: service)
        #if swift(>=4.2)
        RunLoop.current.add(self.timer, forMode: RunLoop.Mode.common)
        #else
        RunLoop.current.add(self.timer, forMode: RunLoopMode.commonModes)
        #endif
    }

    func release() {
        flush()
        self.timer.invalidate()
    }

    func track(name: String, _ data: [String: String]) {
        self.track(metric: Metric(name: name, data: data))
    }

    private func track(metric: Metric) {
        if metric.isValid {
            self.buffer.add(metric: metric)
            if buffer.count(client: false) > bufferLimit {
                flush()
            }
        }
    }

    private func track(metrics: [[String: Any]], client: Bool, completionHandler: ((Bool) -> Void)? = nil) {
        if metrics.count > 0 {
            self.client.post(["metrics": metrics], client: client) { response in
                SDKLogger.shared.debug("\(response)")
                switch response.result {
                case .success:
                    SDKLogger.shared.debug("Success: post metrics")
                    completionHandler?(true)
                case .failure(let error):
                    SDKLogger.shared.error("Failure", error: error)
                    completionHandler?(false)
                }
            }
        }
    }

    @objc func flush() {
        if let metrics = buffer.popAll(client: true) {
            SDKLogger.shared.debug("Clientmetrics flush")
            self.track(metrics: metrics, client: true, completionHandler: nil)
        }
        if let metrics = buffer.popAll(client: false) {
            SDKLogger.shared.debug("Metrics flush")
            self.track(metrics: metrics, client: false, completionHandler: nil)
        }
    }

    func reportMQE(phone: Phone, call: Call, metric: [String: Any]) {
        let identifiers = SparkIdentifiers(call: call, device: phone.devices.device, person: phone.me)
        let clientEvent = ClientEvent(name: .mediaQuality,
                state: nil,
                identifiers: identifiers,
                canProceed: true,
                mediaType: nil,
                csi: nil,
                mediaCapabilities: nil,
                mediaLines: iceMediaLines,
                errors: nil,
                trigger: nil,
                displayLocation: nil,
                dialedDomain: nil,
                labels: nil,
                eventData: nil,
                intervals: [metric])
        let localIP = clientEvent.videoLocalIp ?? "127.0.0.1"
        let clientInfo = ClientInfo(clientType: DeviceService.Types.sdk_client.rawValue, subClientType: "MOBILE_APP", os: "ios", osVersion: UIDevice.current.systemVersion, localIP: localIP, clientVersion: Webex.version)
        let origin = DiagnosticOrigin(userAgent: UserAgent.string,
                networkType: .unknown,
                localIpAddress: localIP,
                usingProxy: false,
                mediaEngineSoftwareVersion: MediaEngineWrapper.sharedInstance.wmeVersion,
                clientInfo: clientInfo)
        let time = DiagnosticOriginTime(triggered: Date().utc, sent: Date().utc)
        let event = DiagnosticEvent(eventId: UUID(),
                version: 1,
                origin: origin,
                originTime: time, event: clientEvent)
        let metric = ClientMetric(event: event, type: "diagnostic-event");
        self.buffer.add(clientMetric: metric)
        if buffer.count(client: true) > bufferLimit {
            flush()
        }
    }

}






