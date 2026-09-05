//
//  LightBoltApp.swift
//  LightBolt
//

import SwiftData
import SwiftUI

@main
struct LightBoltApp: App {
    @State private var entitlements = Entitlements()
    @State private var coach = SpeechCoach()
    @State private var focusLock = FocusLock()
    @State private var auth = AuthManager()
    @State private var account = AccountService()

    private let container: ModelContainer

    init() {
        StripeConfig.configure()
        let schema = Schema([
            UserProfile.self,
            MealEntry.self,
            BodyScan.self,
            SetLog.self,
            WorkoutSession.self,
            Habit.self,
            WeightEntry.self,
            CustomWorkout.self,
            ChallengeProgress.self,
            PlannedWorkout.self
        ])
        do {
            container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            )
        } catch {
            // A corrupt or migration-blocked store must not brick launch —
            // fall back to an in-memory container so the app still runs.
            container = try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(entitlements)
                .environment(coach)
                .environment(focusLock)
                .environment(auth)
                .environment(account)
                .tint(LightBoltTheme.volt)
        }
        .modelContainer(container)
    }
}
