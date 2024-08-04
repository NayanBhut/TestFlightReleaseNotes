//
//  SideBarViewView.swift
//  App Store
//
//  Created by Nayan Bhut on 19/04/24.
//

import SwiftUI

struct SideBarView: View {
    @EnvironmentObject var viewModel: ContentViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack {
            Text("SideBar View")
            HStack {
                Menu("\(viewModel.currentTeam.getAppName())") {
                    ForEach(0..<Team.allCases.count) { teams in
                        Button("\(Team.allCases[teams].getAppName())", action: {
                            viewModel.currentTeam = Team.allCases[teams]
                        })
                    }
                }
                Button(action: {
                    print("Refresh Tapped")
                    viewModel.getAllApps()
                }) {
                    Text("Refresh")
                }
            }
            .disabled(!(viewModel.currentAppState == CurrentAppState.appListLoading))
            appList()
        }
        .padding()
        .onAppear {
            viewModel.getAllApps()
        }.onChange(of: viewModel.currentTeam) { oldValue, newValue in
            viewModel.isAppLoaded = false
            viewModel.updateTeam()
        }
    }
    
    func appList() -> some View {
        VStack {
            if viewModel.isAppLoaded {
                List(viewModel.arrApps) { app in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(app.app.attributes?.name ?? "")")
                                .foregroundColor(.teal)
                            Text("\(app.app.attributes?.bundleID ?? "")")
                                .foregroundStyle(
                                    getAppFontStyle(isSelectedApp: app.isExpanded))
                        }
                        .padding(.leading, 10)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .border(app.isExpanded ? Color.green : Color.clear)
                    .onTapGesture {
                        viewModel.setSelectedAppAndGetVersions(app: app) // Select app and call api to get Builds
                    }
                }
            } else {
                SpinnerView()
            }
            Spacer()
        }
    }
    
    func getAppFontStyle(isSelectedApp: Bool) -> any ShapeStyle {
        let colors: [Color] = isSelectedApp ? [.red] : [.blue]
        
        return LinearGradient(
            colors: colors,
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

#Preview {
    SideBarView()
        .environmentObject(ContentViewModel())
}

//@State var showingDetail = true
//@State private var sizeOfHole = CGSize()
//@State private var positionOfHole = CGPoint()

//                    Button(action: {
//                        viewModel.getAllApps()
//                    }) {
//                        Text("Select Team")
//                    }.background(
//                        GeometryReader { geometry in
//                            Color.blue.onAppear {
//                                print(geometry.frame(in: .global))
//                                sizeOfHole = geometry.frame(in: .global).size
//                                let point = geometry.frame(in: .global).origin
//                                positionOfHole = CGPoint(x: point.x + sizeOfHole.width / 2 + 20 , y: point.y + 20)
//                            }
//                        })


// added this
//extension View {
//    func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
//        background(
//            GeometryReader { geometryProxy in
//                Color.clear
//                    .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
//            }
//        )
//        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
//    }
//}
//
//extension View {
//    func readPosition(onChange: @escaping (CGPoint) -> Void) -> some View {
//        background(
//            GeometryReader { geometryProxy in
//                Color.clear
//                    .preference(key: PositionPreferenceKey.self, value: geometryProxy.frame(in: CoordinateSpace.global).origin)
//            }
//        )
//        .onPreferenceChange(PositionPreferenceKey.self, perform: onChange)
//    }
//}
//
//private struct SizePreferenceKey: PreferenceKey {
//    static var defaultValue: CGSize = .zero
//    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {}
//}
//
//private struct PositionPreferenceKey: PreferenceKey {
//    static var defaultValue: CGPoint = .zero
//    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {}
//}
