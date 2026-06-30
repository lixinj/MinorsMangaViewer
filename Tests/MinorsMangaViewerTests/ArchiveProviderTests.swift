import XCTest
@testable import MinorsMangaViewer

final class ArchiveProviderTests: XCTestCase {
    func testZipPageProviderReadsTestCBZ() async throws {
        let archiveURL = URL(fileURLWithPath: "/tmp/test.cbz")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))

        let provider = try await ArchiveService.provider(for: archiveURL)
        XCTAssertEqual(provider.pageCount, 2)

        let firstImage = try await provider.image(at: 0)
        XCTAssertNotNil(firstImage)

        provider.close()
    }
}
