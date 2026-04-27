import Foundation
import os

/// Offline-first referral service backing the Settings → "Пригласить друга"
/// section (issue #144).
///
/// Stores the user's own 6-character code and the friend's code (if applied)
/// in `UserDefaults`. Bonus credits land via `BalanceService.creditPromotion`
/// so they get a dedicated `.promotion` ledger entry rather than masquerading
/// as a paid `.topup` (which would pollute any future revenue accounting that
/// reads the StoreKit-credit history).
///
/// MVP scope: there is no server, so we cannot actually verify a friend's
/// code belongs to a real user — the validation surface is intentionally
/// minimal (format + self-apply + already-applied) and the service exists
/// mainly to give the screen a clean seam for the eventual real backend.
final class ReferralService {

    static let shared = ReferralService()

    /// Bonus awarded on a successful friend-code apply, in rubles. Matches the
    /// caption text rendered in the Settings section so the two stay in sync
    /// — change here, change the caption.
    static let referralBonusAmount: Double = 200

    /// Errors surfaced to the UI from `applyFriendCode`.
    enum ApplyError: LocalizedError, Equatable {
        /// Code wasn't 6 characters or contained non-alphanumeric symbols
        /// (after normalisation to upper-case).
        case invalidFormat
        /// User has already redeemed a friend-code on this device — bonus
        /// is one-shot.
        case alreadyApplied
        /// User entered their own code.
        case cannotApplyOwnCode
        /// Balance store is locked (corruption — issue #119) so we can't
        /// safely credit. Surfaces the gate to the UI.
        case balanceLocked

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "Код должен содержать 6 символов (буквы и цифры)."
            case .alreadyApplied:
                return "Бонус по реферальному коду уже получен."
            case .cannotApplyOwnCode:
                return "Нельзя применить собственный код."
            case .balanceLocked:
                return "Не удалось зачислить бонус. Попробуйте позже."
            }
        }
    }

    // MARK: - Storage keys

    private let myCodeKey = "referral_my_code"
    private let appliedCodeKey = "referral_applied_code"

    private let defaults: UserDefaults
    private let balanceService: BalanceService
    /// Serial queue protecting the read-then-write on `appliedCodeKey` —
    /// without this two `applyFriendCode` calls racing from different
    /// threads could both observe "not applied yet" and credit the bonus
    /// twice.
    private let queue = DispatchQueue(label: "com.snoozepay.referral.serial")
    private static let log = OSLog(
        subsystem: "Ivan-Emelyanov.SnoozePay",
        category: "ReferralService"
    )

    /// Production code MUST use `ReferralService.shared`. Tests inject custom
    /// `UserDefaults` + `BalanceService` to stay isolated.
    init(defaults: UserDefaults, balanceService: BalanceService) {
        self.defaults = defaults
        self.balanceService = balanceService
    }

    private convenience init() {
        self.init(defaults: .standard, balanceService: .shared)
    }

    // MARK: - Public API

    /// Returns the user's referral code, generating one on first call.
    /// Stable across launches once generated — the code IS the user's
    /// long-term identity in the referral graph.
    func getMyCode() -> String {
        queue.sync {
            if let existing = defaults.string(forKey: myCodeKey),
               isValidFormat(existing) {
                return existing
            }
            let fresh = Self.generateCode()
            defaults.set(fresh, forKey: myCodeKey)
            return fresh
        }
    }

    /// Returns the friend code the user has already redeemed on this device,
    /// if any. The Settings input row uses this to short-circuit re-apply
    /// without round-tripping through the validator.
    var appliedFriendCode: String? {
        queue.sync { defaults.string(forKey: appliedCodeKey) }
    }

    /// Validates `rawCode` and credits the referral bonus on success.
    ///
    /// - Parameter rawCode: User-entered string. Trimmed and upper-cased
    ///   internally so the caller doesn't have to normalise.
    /// - Throws: `ApplyError` describing why the apply was rejected.
    /// - Returns: The amount of rubles credited (matches
    ///   `referralBonusAmount` on the happy path).
    @discardableResult
    func applyFriendCode(_ rawCode: String) throws -> Double {
        let normalised = rawCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard isValidFormat(normalised) else {
            throw ApplyError.invalidFormat
        }

        // Read-then-write under serial queue so concurrent applies cannot
        // both observe "not applied yet" and double-credit the bonus.
        try queue.sync {
            if defaults.string(forKey: appliedCodeKey) != nil {
                throw ApplyError.alreadyApplied
            }
            let myCode = defaults.string(forKey: myCodeKey)
            if let myCode, myCode == normalised {
                throw ApplyError.cannotApplyOwnCode
            }
            // Persist FIRST, then credit. If the credit fails (corrupt
            // balance store) we roll back the persisted code so the user
            // can retry once the corruption is acknowledged. Without this
            // a balance lockout would permanently consume the user's
            // single referral apply slot with no bonus to show for it.
            defaults.set(normalised, forKey: appliedCodeKey)
            let credited = balanceService.creditPromotion(
                amount: Self.referralBonusAmount
            )
            if !credited {
                defaults.removeObject(forKey: appliedCodeKey)
                os_log(
                    "Referral apply rolled back: balance credit refused (likely corruption gate)",
                    log: Self.log, type: .error
                )
                throw ApplyError.balanceLocked
            }
        }
        return Self.referralBonusAmount
    }

    // MARK: - Validation

    /// Letters + digits, 6 chars long, exclude `O`/`0`/`I`/`1` to avoid
    /// hand-copy ambiguity (matches `generateCode`'s alphabet so a code
    /// we generate always validates here).
    private func isValidFormat(_ code: String) -> Bool {
        guard code.count == 6 else { return false }
        return code.unicodeScalars.allSatisfy(Self.alphabetSet.contains)
    }

    // MARK: - Generation

    /// Alphabet excluding visually ambiguous glyphs (`0`/`O`, `1`/`I`).
    /// Lowered to a `Set<Unicode.Scalar>` so `isValidFormat` runs in
    /// O(n) over the input.
    private static let alphabetString = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    private static let alphabetSet: Set<Unicode.Scalar> = {
        Set(alphabetString.unicodeScalars)
    }()

    private static func generateCode() -> String {
        let alphabet = Array(alphabetString)
        var code = ""
        for _ in 0..<6 {
            // `randomElement()` on a non-empty array can only return nil
            // for empty collections, but we still guard so a future edit
            // that empties `alphabetString` fails loudly in tests.
            guard let char = alphabet.randomElement() else {
                assertionFailure("Referral alphabet is empty — fix alphabetString")
                return "AAAAAA"
            }
            code.append(char)
        }
        return code
    }
}
