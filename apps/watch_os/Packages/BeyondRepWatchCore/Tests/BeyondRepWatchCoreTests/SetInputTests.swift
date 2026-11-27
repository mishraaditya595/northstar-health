import XCTest
@testable import BeyondRepWatchCore

final class SetInputTests: XCTestCase {
    func testGramsUseTheBindingUnit() {
        XCTAssertEqual(SetInput.grams(displayWeight: 60, unit: "kg"), 60000)
        XCTAssertEqual(SetInput.grams(displayWeight: 62.5, unit: "kg"), 62500)
        XCTAssertEqual(SetInput.grams(displayWeight: 135, unit: "lb"), 61235)
        XCTAssertEqual(SetInput.grams(displayWeight: 5, unit: "lb"), 2268)
    }

    func testZeroWeightIsNoLoad() {
        XCTAssertNil(SetInput.grams(displayWeight: 0, unit: "kg"))
        XCTAssertNil(SetInput.grams(displayWeight: -2.5, unit: "lb"))
    }

    func testDisplayWeightRoundsToTheCrownStep() {
        XCTAssertEqual(SetInput.displayWeight(grams: 60000, unit: "kg"), 60)
        XCTAssertEqual(SetInput.displayWeight(grams: 61235, unit: "lb"), 135)
        XCTAssertEqual(SetInput.displayWeight(grams: 61000, unit: "kg"), 60)  // 61 kg snaps to 2.5
        XCTAssertEqual(SetInput.displayWeight(grams: nil, unit: "kg"), 0)
    }

    func testStepsAndRanges() {
        XCTAssertEqual(SetInput.step(.weight, unit: "kg"), 2.5)
        XCTAssertEqual(SetInput.step(.weight, unit: "lb"), 5)
        XCTAssertEqual(SetInput.step(.reps, unit: "kg"), 1)
        XCTAssertEqual(SetInput.step(.seconds, unit: "lb"), 5)
        XCTAssertEqual(SetInput.range(.weight, unit: "kg"), 0...500)
        XCTAssertEqual(SetInput.range(.weight, unit: "lb"), 0...1100)
        XCTAssertEqual(SetInput.range(.reps, unit: "kg"), 1...100)
        XCTAssertEqual(SetInput.range(.seconds, unit: "kg"), 5...3600)
    }

    func testClampKeepsAValueInsideItsRange() {
        XCTAssertEqual(SetInput.clamp(900, .weight, unit: "kg"), 500)
        XCTAssertEqual(SetInput.clamp(0, .reps, unit: "kg"), 1)
        XCTAssertEqual(SetInput.clamp(1, .seconds, unit: "kg"), 5)
    }

    func testApplyingAFieldKeepsTheRest() {
        let base = SetValues(setId: "s", exerciseId: "e", position: 0, inputUnit: "kg", reps: 8, loadGrams: 60000)
        XCTAssertEqual(SetInput.applying(65, to: .weight, values: base).loadGrams, 65000)
        XCTAssertEqual(SetInput.applying(65, to: .weight, values: base).reps, 8)
        XCTAssertEqual(SetInput.applying(10, to: .reps, values: base).reps, 10)
        XCTAssertNil(SetInput.applying(0, to: .weight, values: base).loadGrams)
        let timed = SetValues(setId: "s", exerciseId: "e", position: 0, durationSeconds: 45)
        XCTAssertEqual(SetInput.applying(60, to: .seconds, values: timed).durationSeconds, 60)
    }

    func testValueReadsTheFieldInDisplayUnits() {
        let values = SetValues(setId: "s", exerciseId: "e", position: 0, inputUnit: "lb", reps: 8, loadGrams: 61235)
        XCTAssertEqual(SetInput.value(of: .weight, in: values), 135)
        XCTAssertEqual(SetInput.value(of: .reps, in: values), 8)
        XCTAssertEqual(SetInput.value(of: .seconds, in: values), 30)
    }
}
