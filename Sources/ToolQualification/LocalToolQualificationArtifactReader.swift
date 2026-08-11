import CircuiteFoundation
import Foundation

public actor LocalToolQualificationArtifactReader: ToolQualificationArtifactReading {
    private let access: any ArtifactAccessing
    private let availabilities: [ArtifactID: ArtifactAvailability]
    private let budget: ArtifactAccessBudget

    public init(
        access: any ArtifactAccessing,
        availabilities: [ArtifactID: ArtifactAvailability],
        budget: ArtifactAccessBudget
    ) {
        self.access = access
        self.availabilities = availabilities
        self.budget = budget
    }

    public func verifiedData(for reference: ArtifactReference) async throws -> Data {
        guard let availability = availabilities[reference.id] else {
            throw ToolProcessQualificationEvidenceBuildError
                .artifactAvailabilityMissing(reference.id.description)
        }

        let intent: ArtifactAccessIntent
        do {
            intent = try ArtifactAccessIntent(
                expectedReference: reference,
                availability: availability,
                operation: .verify,
                budget: budget
            )
        } catch {
            throw ToolProcessQualificationEvidenceBuildError.artifactAccessFailed(
                String(describing: error)
            )
        }

        let session: any ArtifactReadSession
        do {
            session = try await access.open(intent)
        } catch {
            throw ToolProcessQualificationEvidenceBuildError.artifactAccessFailed(
                String(describing: error)
            )
        }

        do {
            guard reference.byteCount <= UInt64(Int.max) else {
                throw ToolProcessQualificationEvidenceBuildError.artifactAccessFailed(
                    "Artifact byte count exceeds the process address space."
                )
            }
            var data = Data()
            data.reserveCapacity(Int(reference.byteCount))
            var offset: UInt64 = 0
            while true {
                let request = try ArtifactReadPageRequest(
                    offset: offset,
                    maximumByteCount: budget.maximumPageByteCount
                )
                let page = try await session.readPage(request)
                guard page.offset == offset else {
                    throw ToolProcessQualificationEvidenceBuildError.artifactAccessFailed(
                        "Artifact page offset is not contiguous."
                    )
                }
                page.bytes.withUnsafeBytes { bytes in
                    data.append(bytes.bindMemory(to: UInt8.self))
                }
                offset = page.cumulativeByteCount
                switch page.completion {
                case .more:
                    continue
                case .complete:
                    guard offset == reference.byteCount else {
                        throw ToolProcessQualificationEvidenceBuildError
                            .artifactIntegrityFailed(
                                "terminal byte count does not match the content identity"
                            )
                    }
                }
                break
            }
            let termination = await session.close()
            do {
                let receipt = try await termination.wait()
                guard receipt.didReachTerminalPage else {
                    throw ToolProcessQualificationEvidenceBuildError.artifactCloseFailed(
                        "Artifact session closed before its terminal page."
                    )
                }
            } catch let error as ToolProcessQualificationEvidenceBuildError {
                throw error
            } catch {
                throw ToolProcessQualificationEvidenceBuildError.artifactCloseFailed(
                    String(describing: error)
                )
            }
            return data
        } catch let primaryError {
            let termination = await session.close()
            do {
                _ = try await termination.wait()
            } catch {
                throw ToolProcessQualificationEvidenceBuildError.artifactCloseFailed(
                    "primary=\(String(describing: primaryError)); close=\(String(describing: error))"
                )
            }
            if let typed = primaryError as? ToolProcessQualificationEvidenceBuildError {
                throw typed
            }
            throw ToolProcessQualificationEvidenceBuildError.artifactAccessFailed(
                String(describing: primaryError)
            )
        }
    }
}
