#if DEBUG
import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

#Preview("Workout, mid-set") {
    let (model, _) = PreviewData.workoutModel(sets: 1, resting: false)
    return WorkoutView(model: model)
}

#Preview("Workout, rest") {
    let (model, controller) = PreviewData.workoutModel(sets: 1, resting: true)
    return RestPage(model: model, controller: controller)
}

#Preview("Workout, overview") {
    let (model, controller) = PreviewData.workoutModel(sets: 2, resting: false)
    return OverviewPage(model: model, recorder: model.recorder, controller: controller)
}

#Preview("Workout, no sets logged") {
    let (model, controller) = PreviewData.workoutModel(sets: 0, resting: false)
    return EndConfirmView(model: model, controller: controller)
}

#Preview("Workout, exercises") {
    let (model, controller) = PreviewData.workoutModel(sets: 2, resting: false)
    return ExercisesSheet(model: model, controller: controller)
}

#Preview("Workout, summary waiting for iPhone") {
    let model = AppModel(journalURL: FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString).sqlite"))
    model.attachPreview(workout: nil, summary: PreviewData.summary)
    return SummaryView(model: model, summary: PreviewData.summary)
}

#Preview("Plan preview") {
    let (model, _) = PreviewData.workoutModel(sets: 0, resting: false)
    model.attachPreview(workout: nil)
    return NavigationStack { PlanPreviewView(model: model, planId: "plan-preview") }
}
#endif
