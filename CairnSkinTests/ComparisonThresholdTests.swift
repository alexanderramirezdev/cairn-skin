//
//  ComparisonThresholdTests.swift
//  CairnSkinTests
//
//  WHAT THESE GUARD:
//  The percentage is gone, but the raw distance still decides what the
//  compare screen tells the user: "fair to compare," "conditions
//  changed," or "not comparable." These thresholds came from real
//  on-device measurements, and the bands only make sense in one order.
//  These tests pin the boundaries so a casual tweak to one constant can't
//  silently invert the guidance.
//
//  Reference measurements the constants were set from:
//    ~0.20  same subject, photos seconds apart
//    ~0.26  same subject, re-framed using the guide
//    ~0.50  same forearm, same desk, warmer and dimmer light
//    ~0.57  same subject, badly re-framed
//    ~0.96  unrelated object
//

import Testing
@testable import CairnSkin

@Suite("Comparison guidance bands")
struct ComparisonThresholdTests {

    /// The three cut points have to stay strictly ordered or the bands
    /// overlap and a single distance gets two contradictory messages.
    @Test func thresholdsAreStrictlyOrdered() {
        #expect(FeatureExtractor.noiseFloor < FeatureExtractor.framingConcernThreshold)
        #expect(FeatureExtractor.framingConcernThreshold < FeatureExtractor.notComparableThreshold)
    }

    // MARK: - Measured reference points land in the right band

    @Test func samePhotoConditionsIsFairToCompare() {
        let d: Float = 0.204
        #expect(FeatureExtractor.isComparable(distance: d))
        #expect(!FeatureExtractor.framingLooksInconsistent(distance: d))
    }

    @Test func goodReframeWithGuideIsFairToCompare() {
        let d: Float = 0.26
        #expect(FeatureExtractor.isComparable(distance: d))
        #expect(!FeatureExtractor.framingLooksInconsistent(distance: d))
    }

    @Test func changedLightingTriggersTheConditionsNote() {
        let d: Float = 0.4975   // measured: same forearm, same desk, different light
        #expect(FeatureExtractor.isComparable(distance: d))
        #expect(FeatureExtractor.framingLooksInconsistent(distance: d))
    }

    @Test func badReframeTriggersTheConditionsNote() {
        let d: Float = 0.57
        #expect(FeatureExtractor.isComparable(distance: d))
        #expect(FeatureExtractor.framingLooksInconsistent(distance: d))
    }

    @Test func unrelatedObjectIsNotComparable() {
        let d: Float = 0.964    // measured: water bottle against an arm
        #expect(!FeatureExtractor.isComparable(distance: d))
        // Not-comparable outranks the conditions note; they must never
        // both fire for the same pair.
        #expect(!FeatureExtractor.framingLooksInconsistent(distance: d))
    }

    // MARK: - Exact boundaries

    @Test func framingBandIncludesItsLowerEdge() {
        #expect(FeatureExtractor.framingLooksInconsistent(
            distance: FeatureExtractor.framingConcernThreshold))
    }

    @Test func notComparableStartsExactlyAtItsThreshold() {
        let t = FeatureExtractor.notComparableThreshold
        #expect(!FeatureExtractor.isComparable(distance: t))
        #expect(!FeatureExtractor.framingLooksInconsistent(distance: t))
        #expect(FeatureExtractor.isComparable(distance: t.nextDown))
        #expect(FeatureExtractor.framingLooksInconsistent(distance: t.nextDown))
    }

    /// Every distance gets exactly one of the three messages.
    @Test(arguments: stride(from: Float(0), through: 1.5, by: 0.01).map { $0 })
    func everyDistanceGetsExactlyOneMessage(distance: Float) {
        let fair = FeatureExtractor.isComparable(distance: distance)
            && !FeatureExtractor.framingLooksInconsistent(distance: distance)
        let conditions = FeatureExtractor.framingLooksInconsistent(distance: distance)
        let notComparable = !FeatureExtractor.isComparable(distance: distance)

        let messagesShown = [fair, conditions, notComparable].filter { $0 }.count
        #expect(messagesShown == 1)
    }

    // MARK: - Extraction pipeline version

    /// Bump `extractionGeneration` whenever the crop or extraction
    /// changes, or stored vectors silently stop matching new ones. This
    /// can't detect a forgotten bump, but it makes the current value a
    /// deliberate, reviewed number: changing it means changing this test,
    /// which is the prompt to ask whether the migration is right.
    @Test func extractionGenerationIsTheReviewedValue() {
        #expect(FeatureExtractor.extractionGeneration == 2)
    }
}
