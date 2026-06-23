import XCTest
@testable import VirtualFaceCamApp

final class VirtualFaceCamAppTests: XCTestCase {
    func testDependencyContainerLiveBuilds() {
        let container = DependencyContainer.live
        XCTAssertNotNil(container.videoCapture)
        XCTAssertNotNil(container.faceTracking)
        XCTAssertNotNil(container.avatarEngine)
        XCTAssertNotNil(container.renderer)
        XCTAssertNotNil(container.virtualCamera)
    }
}
