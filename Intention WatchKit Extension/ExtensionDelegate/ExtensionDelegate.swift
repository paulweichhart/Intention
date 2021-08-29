//
//  ExtensionDelegate.swift
//  Intention WatchKit Extension
//
//  Created by Paul Weichhart on 24.10.20.
//

import ClockKit
import Foundation
import WatchKit
import HealthKit

final class ExtensionDelegate: NSObject, WKExtensionDelegate {
    
    private let mindfulTimeIntervalKey = "mindfulTimeInterval"
    private let store = Store.shared

    func applicationDidBecomeActive() {
        Task {
            await registerBackgroundDelivery()
        }
    }

    func applicationDidEnterBackground() {
        Task {
            let mindfulTimeInterval = await fetchMindfulTimeInterval() ?? 0
            scheduleBackgroundRefresh(mindfulTimeInterval: mindfulTimeInterval)
            updateActiveComplications(shouldReload: true)
        }
    }
    
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {

            case let backgroundTask as WKApplicationRefreshBackgroundTask:
                let userInfo = backgroundTask.userInfo as? NSDictionary
                let cachedTimeInterval = userInfo?[mindfulTimeIntervalKey] as? TimeInterval ?? 0
                
                Task {
                    let mindfulTimeInterval = await fetchMindfulTimeInterval() ?? cachedTimeInterval
                    let shouldReload = mindfulTimeInterval != cachedTimeInterval
                    scheduleBackgroundRefresh(mindfulTimeInterval: mindfulTimeInterval)
                    updateActiveComplications(shouldReload: shouldReload)
                    backgroundTask.setTaskCompletedWithSnapshot(shouldReload)
                }

            case let snapshotTask as WKSnapshotRefreshBackgroundTask:
                snapshotTask.setTaskCompleted(restoredDefaultState: true,
                                              estimatedSnapshotExpiration: Date.distantFuture,
                                              userInfo: nil)
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    private func fetchMindfulTimeInterval() async -> TimeInterval? {
        await store.dispatch(action: .requestHealthStorePermission)
        await store.dispatch(action: .fetchMindfulTimeInterval)
        switch store.state.mindfulState {
        case let .loaded(mindfulTimeInterval):
            return mindfulTimeInterval
        case .error, .loading:
            return nil
        }
    }
    
    private func updateActiveComplications(shouldReload: Bool) {
        let complicationServer = CLKComplicationServer.sharedInstance()
        if let activeComplications = complicationServer.activeComplications {
            for complication in activeComplications {
                if shouldReload {
                    complicationServer.reloadTimeline(for: complication)
                } else {
                    complicationServer.extendTimeline(for: complication)
                }
            }
        }
    }

    private func registerBackgroundDelivery() async {
        await store.dispatch(action: .startObservingMindfulStoreChanges({ [weak self] in
            let currentState = self?.store.state.mindfulState
            await self?.store.dispatch(action: .requestHealthStorePermission)
            await self?.store.dispatch(action: .fetchMindfulTimeInterval)
            if currentState != self?.store.state.mindfulState {
                self?.updateActiveComplications(shouldReload: true)
            }
        }))
    }

    private func scheduleBackgroundRefresh(mindfulTimeInterval: TimeInterval) {
        let scheduledDate = Date().addingTimeInterval(Converter.timeInterval(from: 15))
        let userInfo: NSDictionary = [mindfulTimeIntervalKey: mindfulTimeInterval]
        WKExtension.shared().scheduleBackgroundRefresh(withPreferredDate: scheduledDate,
                                                       userInfo: userInfo,
                                                       scheduledCompletion: { _ in })
    }
}
