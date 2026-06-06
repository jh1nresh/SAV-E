import XCTest
@testable import SAVE

final class VerifiedPlaceClaimsClientTests: XCTestCase {
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
    }

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

    func testPlaceRecoveryWorkflowRunDecodesResultState() throws {
        let runId = UUID()
        let candidateId = UUID()
        let json = """
        {
          "id": "\(runId.uuidString)",
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
        XCTAssertEqual(run.workflowId, "save_place_recovery_v0")
        XCTAssertEqual(run.status, "needs_review")
        XCTAssertEqual(run.resultCandidateRefs, [candidateId.uuidString])
    }

    func testPlaceRecoveryDraftsBuildBackendBodiesAndDecodeReceipt() throws {
        let runId = UUID()
        let receiptId = UUID()
        let candidateId = UUID()
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
            editedPayload: ["place_id": "place_123"],
            reason: "User saved review candidate as confirmed Map Stamp."
        )

        XCTAssertEqual(result.body["result_type"] as? String, "review_candidate")
        XCTAssertEqual(result.body["evidence_tier"] as? String, "likely")
        XCTAssertEqual(result.body["candidate_refs"] as? [String], [candidateId.uuidString])
        XCTAssertEqual(decision.body["action"] as? String, "confirm")
        XCTAssertEqual(decision.body["reason"] as? String, "User saved review candidate as confirmed Map Stamp.")

        let json = """
        {
          "run": {
            "id": "\(runId.uuidString)",
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
        XCTAssertEqual(response.receipt.id, receiptId)
        XCTAssertEqual(response.receipt.verdict, "pass")
        XCTAssertEqual(response.receipt.candidateRefs, [candidateId.uuidString])
    }
}
