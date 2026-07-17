import XCTest
@testable import SAVE

final class VerifiedPlaceClaimsClientTests: XCTestCase {
    @MainActor
    func testVerifiedPlaceClaimDecodesSnakeCaseResponse() throws {
        let claimId = UUID()
        let placeId = UUID()
        let json = """
        {
          "claim_id": "\(claimId.uuidString)",
          "place_id": "\(placeId.uuidString)",
          "claim_type": "visited",
          "claim": "Tried the matcha latte.",
          "agent_usable_summary": "User tried the matcha latte.",
          "author": {
            "author_type": "self",
            "public_handle": null,
            "relationship": "self"
          },
          "proof_level": "user_confirmed_place",
          "confidence": 0.82,
          "visibility": "private",
          "evidence_summary": ["Saved by user"],
          "evidence_refs": ["save://memory/1"],
          "observed_at": "2026-06-03T10:00:00Z",
          "expires_or_stale_after": null,
          "created_at": "2026-06-03T10:01:00Z"
        }
        """.data(using: .utf8)!

        let claim = try JSONDecoder.supabase.decode(VerifiedPlaceClaim.self, from: json)

        XCTAssertEqual(claim.id, claimId)
        XCTAssertEqual(claim.placeId, placeId)
        XCTAssertEqual(claim.claimType, "visited")
        XCTAssertEqual(claim.author.relationship, "self")
        XCTAssertEqual(claim.evidenceRefs, ["save://memory/1"])
    }

    @MainActor
    func testVerifiedPlaceClaimDraftBuildsBackendBody() throws {
        let draft = VerifiedPlaceClaimDraft(
            claimType: "menu_item",
            claim: "Has milk tea.",
            agentUsableSummary: "Milk tea evidence is user-confirmed.",
            proofLevel: "user_confirmed_place",
            evidenceRefs: ["save://source/1"],
            visibility: "private",
            confidence: 0.74,
            context: ["query": "milk tea"],
            ratings: ["taste": 4],
            observedAt: "2026-06-03T10:00:00Z",
            expiresOrStaleAfter: nil
        )

        XCTAssertEqual(draft.body["claim_type"] as? String, "menu_item")
        XCTAssertEqual(draft.body["agent_usable_summary"] as? String, "Milk tea evidence is user-confirmed.")
        XCTAssertEqual(draft.body["proof_level"] as? String, "user_confirmed_place")
        XCTAssertEqual(draft.body["evidence_refs"] as? [String], ["save://source/1"])
        XCTAssertEqual(draft.body["visibility"] as? String, "private")
        XCTAssertEqual(draft.body["confidence"] as? Double, 0.74)
    }

    @MainActor
    func testClaimRecommendationResponseDecodesRetrievalReceipt() throws {
        let placeId = UUID()
        let claimId = UUID()
        let json = """
        {
          "results": [
            {
              "place_id": "\(placeId.uuidString)",
              "name": "Kato",
              "why": "matches menu_item; strongest proof is user_confirmed_place",
              "proof_level": "user_confirmed_place",
              "confidence": 0.91,
              "supporting_claims": ["\(claimId.uuidString)"],
              "warnings": [],
              "next_actions": ["view_card", "get_trust_summary"]
            }
          ],
          "retrieval_receipt": {
            "used": ["1 owner-scoped places", "1 verified claims"],
            "skipped": [],
            "public_web_used": false
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.supabase.decode(ClaimRecommendationResponse.self, from: json)

        XCTAssertEqual(response.results.first?.id, placeId)
        XCTAssertEqual(response.results.first?.supportingClaims, [claimId])
        XCTAssertEqual(response.retrievalReceipt.used, ["1 owner-scoped places", "1 verified claims"])
        XCTAssertFalse(response.retrievalReceipt.publicWebUsed)
        XCTAssertNil(response.agentShackReceiptEnvelope)
    }

    @MainActor
    func testClaimRecommendationResponseDecodesAgentShackEnvelope() throws {
        let placeId = UUID()
        let claimId = UUID()
        let json = """
        {
          "results": [
            {
              "place_id": "\(placeId.uuidString)",
              "name": "Kato",
              "why": "matches menu_item; strongest proof is user_confirmed_place",
              "proof_level": "user_confirmed_place",
              "confidence": 0.91,
              "supporting_claims": ["\(claimId.uuidString)"],
              "warnings": [],
              "next_actions": ["view_card", "get_trust_summary"]
            }
          ],
          "retrieval_receipt": {
            "used": ["1 owner-scoped places", "1 verified claims"],
            "skipped": [],
            "public_web_used": false
          },
          "agent_shack_receipt_envelope": {
            "product": "save",
            "receipt_type": "recommendation_analysis",
            "user_id": "user_123",
            "agent_id": "save-ios",
            "capability": "place_claim_recommendation",
            "input_hash": "input_hash_123",
            "output_hash": "output_hash_123",
            "private_payload_ref": "save://receipts/recommendation_analysis/receipt_123",
            "public_summary": {
              "summary": "SAV-E analyzed owner-scoped saved places and kept public discovery separate.",
              "capability": "place_claim_recommendation",
              "result_count": 1,
              "saved_result_count": 1,
              "public_result_count": 0,
              "proof_level_min": "user_confirmed_place",
              "public_web_used": false
            },
            "preference_signals": ["coffee", "nearby", "proof_level:user_confirmed_place"],
            "evaluator_verdict": "pass",
            "settlement_state": "not_settled",
            "created_at": "2026-06-06T12:00:00Z"
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.supabase.decode(ClaimRecommendationResponse.self, from: json)
        let envelope = try XCTUnwrap(response.agentShackReceiptEnvelope)

        XCTAssertEqual(envelope.product, "save")
        XCTAssertEqual(envelope.receiptType, "recommendation_analysis")
        XCTAssertEqual(envelope.capability, "place_claim_recommendation")
        XCTAssertEqual(envelope.privatePayloadRef, "save://receipts/recommendation_analysis/receipt_123")
        XCTAssertEqual(envelope.publicSummary.resultCount, 1)
        XCTAssertEqual(envelope.publicSummary.publicResultCount, 0)
        XCTAssertEqual(envelope.preferenceSignals, ["coffee", "nearby", "proof_level:user_confirmed_place"])
        XCTAssertEqual(envelope.evaluatorVerdict, "pass")
        XCTAssertEqual(envelope.settlementState, "not_settled")
    }

    @MainActor
    func testRecommendationAnalysisInternalReceiptKeepsAgentShackProjectionSafe() throws {
        let receiptId = UUID()
        let envelope = AgentShackReceiptEnvelope(
            product: "save",
            receiptType: "recommendation_analysis",
            userId: "user_123",
            agentId: "save-ios",
            capability: "place_claim_recommendation",
            inputHash: "input_hash_123",
            outputHash: "output_hash_123",
            privatePayloadRef: "save://receipts/recommendation_analysis/\(receiptId.uuidString)",
            publicSummary: RecommendationAnalysisPublicSummary(
                summary: "SAV-E analyzed owner-scoped saved places and kept public discovery separate.",
                capability: "place_claim_recommendation",
                resultCount: 1,
                savedResultCount: 1,
                publicResultCount: 0,
                proofLevelMin: "user_confirmed_place",
                publicWebUsed: false
            ),
            preferenceSignals: ["coffee", "nearby"],
            evaluatorVerdict: "pass",
            settlementState: "not_settled",
            createdAt: "2026-06-06T12:00:00Z"
        )
        let internalReceipt = SaveRecommendationAnalysisReceipt(
            id: receiptId,
            envelope: envelope,
            fullPayloadJSON: #"{"result_name":"Utopia Euro Caffe","private_note":"birthday plan"}"#
        )

        let projection = internalReceipt.agentShackProjection
        let encodedProjection = try JSONEncoder.supabase.encode(projection)
        let projectionJSON = String(data: encodedProjection, encoding: .utf8) ?? ""

        XCTAssertEqual(projection.receiptType, "recommendation_analysis")
        XCTAssertTrue(projectionJSON.contains("private_payload_ref"))
        XCTAssertFalse(projectionJSON.contains("full_payload_json"))
        XCTAssertFalse(projectionJSON.contains("Utopia Euro Caffe"))
        XCTAssertFalse(projectionJSON.contains("birthday plan"))
    }

    @MainActor
    func testPublicPlaceCardDecodesPublicProjection() throws {
        let placeId = UUID()
        let claimId = UUID()
        let json = """
        {
          "card_id": "\(placeId.uuidString)",
          "title": "Kato",
          "place": {
            "id": "\(placeId.uuidString)",
            "name": "Kato",
            "city": "Los Angeles",
            "address": "777 Alameda St",
            "category": "food"
          },
          "summary": "Great date dinner.",
          "public_claims": [
            {
              "claim_id": "\(claimId.uuidString)",
              "place_id": "\(placeId.uuidString)",
              "claim_type": "good_for_date",
              "claim": "Great date dinner.",
              "agent_usable_summary": "Date dinner",
              "author": {
                "author_type": "self",
                "public_handle": "memo",
                "relationship": "self"
              },
              "proof_level": "visited_self_reported",
              "confidence": 0.82,
              "visibility": "public",
              "evidence_summary": ["saved source evidence"],
              "observed_at": null,
              "expires_or_stale_after": null,
              "created_at": "2026-06-03T10:01:00Z"
            }
          ],
          "trust_summary": {
            "verified_claim_count": 1,
            "receipt_backed_count": 0,
            "friend_verified_count": 0,
            "last_observed_at": null,
            "strongest_proof_level": "visited_self_reported",
            "confidence": 0.82,
            "reputation": {
              "usage_count": 3,
              "accepted_count": 2,
              "score": 0.67
            },
            "recommended_use": ["recommend", "cite"],
            "warnings": []
          },
          "agent_actions": ["cite_card", "save_to_vault"]
        }
        """.data(using: .utf8)!

        let card = try JSONDecoder.supabase.decode(PublicPlaceCard.self, from: json)

        XCTAssertEqual(card.id, placeId)
        XCTAssertEqual(card.place.name, "Kato")
        XCTAssertEqual(card.publicClaims.first?.id, claimId)
        XCTAssertEqual(card.trustSummary.reputation?.usageCount, 3)
        XCTAssertEqual(card.agentActions, ["cite_card", "save_to_vault"])
    }

    @MainActor
    func testClaimUsageReceiptDraftBuildsBodyAndDecodesResponse() throws {
        let claimId = UUID()
        let placeId = UUID()
        let receiptId = UUID()
        let draft = ClaimUsageReceiptDraft(
            claimId: claimId,
            consumerAgentId: "save-ios",
            action: "recommended_to_user",
            outcome: "accepted"
        )

        XCTAssertEqual(draft.body["claim_id"] as? String, claimId.uuidString)
        XCTAssertEqual(draft.body["consumer_agent_id"] as? String, "save-ios")
        XCTAssertEqual(draft.body["action"] as? String, "recommended_to_user")
        XCTAssertEqual(draft.body["outcome"] as? String, "accepted")

        let json = """
        {
          "id": "\(receiptId.uuidString)",
          "claim_id": "\(claimId.uuidString)",
          "place_id": "\(placeId.uuidString)",
          "consumer_agent_id": "save-ios",
          "consumer_user_id": null,
          "action": "recommended_to_user",
          "outcome": "accepted",
          "created_at": "2026-06-03T10:01:00Z"
        }
        """.data(using: .utf8)!

        let receipt = try JSONDecoder.supabase.decode(ClaimUsageReceipt.self, from: json)

        XCTAssertEqual(receipt.id, receiptId)
        XCTAssertEqual(receipt.claimId, claimId)
        XCTAssertEqual(receipt.placeId, placeId)
        XCTAssertEqual(receipt.consumerAgentId, "save-ios")
    }

    @MainActor
    func testPlaceRecoveryWorkflowRunDecodesResultState() throws {
        let workOrderId = UUID()
        let runId = UUID()
        let candidateId = UUID()
        let json = """
        {
          "id": "\(runId.uuidString)",
          "work_order_id": "\(workOrderId.uuidString)",
          "workflow_id": "save_place_recovery_v0",
          "listing_id": "save-place-recovery-agent",
          "source_url": "https://www.instagram.com/reel/example/",
          "source_type": "instagram",
          "status": "needs_review",
          "result_type": "review_candidate",
          "confidence": 0.82,
          "evidence_tier": "likely",
          "result_evidence_refs": ["source_url:https://www.instagram.com/reel/example/"],
          "result_candidate_refs": ["\(candidateId.uuidString)"],
          "credit_reserved": 1,
          "credit_settlement": "pending",
          "receipt_id": null,
          "created_at": "2026-06-06T10:00:00Z",
          "completed_at": null
        }
        """.data(using: .utf8)!

        let run = try JSONDecoder.supabase.decode(PlaceRecoveryWorkflowRun.self, from: json)

        XCTAssertEqual(run.id, runId)
        XCTAssertEqual(run.workOrderId, workOrderId)
        XCTAssertEqual(run.workflowId, "save_place_recovery_v0")
        XCTAssertEqual(run.status, "needs_review")
        XCTAssertEqual(run.resultCandidateRefs, [candidateId.uuidString])
    }

    @MainActor
    func testPlaceRecoveryResultEnvelopeReturnsRun() throws {
        let runId = UUID()
        let receiptId = UUID()
        let candidateId = UUID()
        let json = """
        {
          "run": {
            "id": "\(runId.uuidString)",
            "work_order_id": null,
            "workflow_id": "save_place_recovery_v0",
            "listing_id": "save-place-recovery-agent",
            "source_url": "https://example.com/source",
            "source_type": "url",
            "status": "needs_review",
            "result_type": "review_candidate",
            "confidence": 0.82,
            "evidence_tier": "likely",
            "result_evidence_refs": ["opaque:sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
            "result_candidate_refs": ["\(candidateId.uuidString)"],
            "credit_reserved": 1,
            "credit_settlement": "pending",
            "receipt_id": "\(receiptId.uuidString)",
            "created_at": "2026-07-10T05:11:25Z",
            "completed_at": null
          },
          "receipt": {
            "id": "\(receiptId.uuidString)",
            "run_id": "\(runId.uuidString)",
            "workflow_id": "save_place_recovery_v0",
            "verdict": "pass",
            "settlement": "manual_review",
            "evaluator_summary": "Analysis produced a review candidate.",
            "evidence_refs": ["opaque:sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
            "candidate_refs": ["\(candidateId.uuidString)"],
            "receipt_hash": "hash_123",
            "anchor_status": "offchain",
            "private_url": null,
            "created_at": "2026-07-10T05:11:26Z"
          }
        }
        """.data(using: .utf8)!

        let run = try SupabaseService.decodePlaceRecoveryResultResponse(json)

        XCTAssertEqual(run.id, runId)
        XCTAssertEqual(run.status, "needs_review")
        XCTAssertEqual(run.resultCandidateRefs, [candidateId.uuidString])
    }

    @MainActor
    func testPlaceRecoveryResponseDecodingErrorDoesNotBecomeTechnicalFailure() {
        let malformedEnvelope = "{}".data(using: .utf8)!

        XCTAssertThrowsError(try SupabaseService.decodePlaceRecoveryResultResponse(malformedEnvelope)) { error in
            XCTAssertTrue(error is DecodingError)
            XCTAssertFalse(MapViewModel.shouldRecordPlaceRecoveryTechnicalFailure(for: error))
        }
        XCTAssertTrue(MapViewModel.shouldRecordPlaceRecoveryTechnicalFailure(
            for: SupabaseError.apiError(500, "server error")
        ))
    }

    @MainActor
    func testSourceSearchRecoveryDecodesSourceResolutionContract() throws {
        let json = """
        {
          "created_candidates": [],
          "source_resolution": {
            "original_url": "http://xhslink.com/m/66nsbd6V2We",
            "resolved_url": "https://www.xiaohongshu.com/discovery/item/6a20eacb000000000f03ac00",
            "redirect_chain": [
              "http://xhslink.com/m/66nsbd6V2We",
              "https://www.xiaohongshu.com/discovery/item/6a20eacb000000000f03ac00"
            ],
            "canonical_content_id": "6a20eacb000000000f03ac00",
            "status": "resolved",
            "title": "先斗町しゃぶしゃぶすき焼き きらく",
            "caption": "京都府京都市中京区先斗町通四条上る柏屋町169-2",
            "thumbnail_url": "https://example.com/kiraku.jpg"
          }
        }
        """.data(using: .utf8)!

        let result = try SupabaseService.decodeSourceSearchRecoveryResponse(json)

        XCTAssertTrue(result.createdCandidates.isEmpty)
        XCTAssertEqual(result.sourceResolution?.status, .resolved)
        XCTAssertEqual(result.sourceResolution?.originalURL, "http://xhslink.com/m/66nsbd6V2We")
        XCTAssertEqual(
            result.sourceResolution?.resolvedURL,
            "https://www.xiaohongshu.com/discovery/item/6a20eacb000000000f03ac00"
        )
        XCTAssertEqual(result.sourceResolution?.canonicalContentID, "6a20eacb000000000f03ac00")
        XCTAssertEqual(result.sourceResolution?.redirectChain.count, 2)
        XCTAssertEqual(result.sourceResolution?.thumbnailURL, "https://example.com/kiraku.jpg")
    }

    @MainActor
    func testPlaceRecoveryWorkOrderDecodesAgentClearingFields() throws {
        let workOrderId = UUID()
        let json = """
        {
          "id": "\(workOrderId.uuidString)",
          "workflow_id": "save_place_recovery_v0",
          "listing_id": "save-place-recovery-agent",
          "intent": "recover_place_from_source",
          "input_type": "url",
          "input_ref": "https://www.instagram.com/reel/example/",
          "source_url": "https://www.instagram.com/reel/example/",
          "evaluator_policy_id": "save_place_recovery_v0",
          "settlement_mode": "credit_after_decision",
          "status": "queued",
          "created_at": "2026-06-06T10:00:00Z"
        }
        """.data(using: .utf8)!

        let workOrder = try JSONDecoder.supabase.decode(PlaceRecoveryWorkOrder.self, from: json)

        XCTAssertEqual(workOrder.id, workOrderId)
        XCTAssertEqual(workOrder.intent, "recover_place_from_source")
        XCTAssertEqual(workOrder.evaluatorPolicyId, "save_place_recovery_v0")
        XCTAssertEqual(workOrder.settlementMode, "credit_after_decision")
    }

    @MainActor
    func testPlaceRecoveryDraftsBuildBackendBodiesAndDecodeReceipt() throws {
        let workOrderId = UUID()
        let runId = UUID()
        let receiptId = UUID()
        let candidateId = UUID()
        let finalPlace = Place.mock
        let finalPlaceId = finalPlace.id
        let result = PlaceRecoveryResultDraft(
            resultType: "review_candidate",
            evidenceTier: "likely",
            confidence: 0.78,
            evidenceRefs: ["source_url:https://example.com"],
            candidateRefs: [candidateId.uuidString],
            technicalFailure: false
        )
        let decision = PlaceRecoveryDecisionDraft(
            action: "confirm",
            candidateId: candidateId,
            finalPlaceId: finalPlaceId,
            finalPlace: finalPlace,
            reasonCode: "confirm_candidate",
            editedPayload: ["place_id": finalPlaceId.uuidString],
            reason: "User saved review candidate as confirmed Map Stamp."
        )

        XCTAssertEqual(result.body["result_type"] as? String, "review_candidate")
        XCTAssertEqual(result.body["evidence_tier"] as? String, "likely")
        XCTAssertEqual(result.body["candidate_refs"] as? [String], [candidateId.uuidString])
        XCTAssertEqual(decision.body["action"] as? String, "confirm")
        XCTAssertEqual(decision.body["candidate_id"] as? String, candidateId.uuidString)
        XCTAssertEqual(decision.body["final_place_id"] as? String, finalPlaceId.uuidString)
        XCTAssertEqual(decision.body["reason_code"] as? String, "confirm_candidate")
        XCTAssertEqual((decision.body["final_place"] as? [String: Any])?["id"] as? String, finalPlaceId.uuidString)
        XCTAssertEqual((decision.body["final_place"] as? [String: Any])?["name"] as? String, finalPlace.name)
        XCTAssertEqual(decision.body["reason"] as? String, "User saved review candidate as confirmed Map Stamp.")

        let json = """
        {
          "run": {
            "id": "\(runId.uuidString)",
            "work_order_id": "\(workOrderId.uuidString)",
            "workflow_id": "save_place_recovery_v0",
            "listing_id": "save-place-recovery-agent",
            "source_url": "https://example.com",
            "source_type": "url",
            "status": "completed",
            "result_type": "review_candidate",
            "confidence": 0.78,
            "evidence_tier": "likely",
            "result_evidence_refs": ["source_url:https://example.com"],
            "result_candidate_refs": ["\(candidateId.uuidString)"],
            "credit_reserved": 1,
            "credit_settlement": "consumed",
            "receipt_id": "\(receiptId.uuidString)",
            "created_at": "2026-06-06T10:00:00Z",
            "completed_at": "2026-06-06T10:01:00Z"
          },
          "receipt": {
            "id": "\(receiptId.uuidString)",
            "run_id": "\(runId.uuidString)",
            "workflow_id": "save_place_recovery_v0",
            "verdict": "pass",
            "settlement": "credit_consumed",
            "evaluator_summary": "Place recovery produced a confirmed map stamp or user accepted the candidate.",
            "evidence_refs": ["source_url:https://example.com"],
            "candidate_refs": ["\(candidateId.uuidString)"],
            "receipt_hash": "hash_123",
            "anchor_status": "offchain",
            "private_url": null,
            "created_at": "2026-06-06T10:01:00Z"
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.supabase.decode(PlaceRecoveryDecisionReceiptResponse.self, from: json)

        XCTAssertEqual(response.run.id, runId)
        XCTAssertEqual(response.run.workOrderId, workOrderId)
        XCTAssertEqual(response.receipt.id, receiptId)
        XCTAssertEqual(response.receipt.verdict, "pass")
        XCTAssertEqual(response.receipt.candidateRefs, [candidateId.uuidString])
    }

    @MainActor
    func testPlaceRecoveryDecisionStripsGooglePhotoKeysFromFinalPlacePayload() throws {
        let legacyURL = "https://maps.googleapis.com/maps/api/place/photo?maxwidth=900&photo_reference=legacy-ref&key=TEST_ONLY_NON_SECRET_VALUE"
        var finalPlace = Place.mock
        finalPlace.sourceImageUrl = legacyURL
        finalPlace.businessPhotoUrls = [legacyURL]
        let decision = PlaceRecoveryDecisionDraft(
            action: "confirm",
            finalPlaceId: finalPlace.id,
            finalPlace: finalPlace,
            editedPayload: [:]
        )

        let payload = try XCTUnwrap(decision.body["final_place"] as? [String: Any])
        XCTAssertFalse(try XCTUnwrap(payload["source_image_url"] as? String).contains("key="))
        XCTAssertFalse(try XCTUnwrap((payload["business_photo_urls"] as? [String])?.first).contains("key="))
    }

    @MainActor
    func testTechnicalFailureDraftCarriesStructuredStageWithoutRawErrorText() {
        let result = PlaceRecoveryResultDraft(
            resultType: "technical_failure",
            evidenceTier: "none",
            confidence: 0,
            evidenceRefs: ["artifact:opaque_1"],
            candidateRefs: [],
            technicalFailure: true,
            failureCode: "candidate_persistence_failed",
            failedStep: "persist_candidate",
            retryable: true
        )

        XCTAssertEqual(result.body["failure_code"] as? String, "candidate_persistence_failed")
        XCTAssertEqual(result.body["failed_step"] as? String, "persist_candidate")
        XCTAssertEqual(result.body["retryable"] as? Bool, true)
        XCTAssertFalse((result.body["evidence_refs"] as? [String] ?? []).contains { $0.contains("error:") })
    }
}
