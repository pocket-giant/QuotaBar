import Testing
import Foundation

@Suite("PopoverLayout")
@MainActor
struct PopoverLayoutTests {

    /// Matches `UsagePopoverView.matrixOuterWidth`: label column + one column per account
    /// + hairline separators + the matrix's horizontal padding.
    private func matrixOuterWidth(accounts: Int) -> CGFloat {
        UsageMatrixView.labelWidth
            + UsageMatrixView.columnWidth * CGFloat(accounts)
            + CGFloat(max(accounts - 1, 0)) * UsageMatrixView.columnSpacing
            + 32
    }

    @Test("A single account keeps the 320-pt column whatever the matrix would need")
    func singleAccount() {
        #expect(PopoverLayout.width(accountCount: 1, matrixOuterWidth: matrixOuterWidth(accounts: 1),
                                    visibleWidth: 1440) == 320)
        #expect(PopoverLayout.width(accountCount: 1, matrixOuterWidth: 5000, visibleWidth: 1440) == 320)
        #expect(PopoverLayout.width(accountCount: 0, matrixOuterWidth: 5000, visibleWidth: 1440) == 320)
    }

    @Test("Four accounts fit a 1440-wide screen: full matrix width, no horizontal scrolling")
    func fourAccountsFit() {
        let outer = matrixOuterWidth(accounts: 4)  // 4*236 + 30 + 32 = 1006
        #expect(PopoverLayout.width(accountCount: 4, matrixOuterWidth: outer, visibleWidth: 1440) == outer)
        #expect(PopoverLayout.scrolls(matrixOuterWidth: outer, visibleWidth: 1440) == false)
    }

    @Test("Ten accounts overflow a 1440-wide screen: clamped to the screen, scrolls")
    func tenAccountsScroll() {
        let outer = matrixOuterWidth(accounts: 10)  // 10*236 + 90 + 32 = 2482
        #expect(outer > 1440)
        #expect(PopoverLayout.width(accountCount: 10, matrixOuterWidth: outer, visibleWidth: 1440) == 1400)
        #expect(PopoverLayout.scrolls(matrixOuterWidth: outer, visibleWidth: 1440) == true)
    }

    @Test("A screen narrower than the minimum never squeezes the popover below 320")
    func narrowScreen() {
        let outer = matrixOuterWidth(accounts: 2)
        #expect(PopoverLayout.width(accountCount: 2, matrixOuterWidth: outer, visibleWidth: 300) == 320)
        #expect(PopoverLayout.scrolls(matrixOuterWidth: outer, visibleWidth: 300) == true)
    }

    @Test("The old 680-pt cap is gone: four accounts draw wider than it")
    func oldCapGone() {
        let outer = matrixOuterWidth(accounts: 4)
        #expect(PopoverLayout.width(accountCount: 4, matrixOuterWidth: outer, visibleWidth: 1440) > 680)
    }
}
