import Contacts
import Foundation

enum ContactsBridge {
    private static let store = CNContactStore()

    static func requestAccess() async -> Bool {
        await withCheckedContinuation { cont in
            store.requestAccess(for: .contacts) { granted, _ in
                cont.resume(returning: granted)
            }
        }
    }

    static func authorizationStatus() -> CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    // MARK: - Keys

    // Reason: CNContactNoteKey requires a restricted entitlement since macOS 11
    // and is deliberately omitted here — requesting it would fail the fetch.
    private static var defaultKeys: [CNKeyDescriptor] {
        let stringKeys: [CNKeyDescriptor] = [
            CNContactIdentifierKey,
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactMiddleNameKey,
            CNContactNicknameKey,
            CNContactOrganizationNameKey,
            CNContactJobTitleKey,
            CNContactEmailAddressesKey,
            CNContactPhoneNumbersKey,
            CNContactPostalAddressesKey,
            CNContactBirthdayKey,
            CNContactUrlAddressesKey,
            CNContactImageDataAvailableKey
        ].map { $0 as CNKeyDescriptor }
        return stringKeys + [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
        ]
    }

    // MARK: - Public API

    static func listGroups() async {
        guard await requestAccess() else {
            JSONOutput.error("Contacts access denied. Grant access in System Settings > Privacy & Security > Contacts.")
            return
        }
        do {
            let groups = try store.groups(matching: nil)
            let result: [[String: Any]] = try groups.map { g in
                let predicate = CNContact.predicateForContactsInGroup(withIdentifier: g.identifier)
                let members = try store.unifiedContacts(
                    matching: predicate,
                    keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]
                )
                return [
                    "id": g.identifier,
                    "name": g.name,
                    "memberCount": members.count
                ]
            }
            JSONOutput.success(result)
        } catch {
            JSONOutput.error("Failed to list groups: \(error.localizedDescription)")
        }
    }

    static func search(query: String, limit: Int) async {
        guard await requestAccess() else {
            JSONOutput.error("Contacts access denied. Grant access in System Settings > Privacy & Security > Contacts.")
            return
        }
        let results = findMatches(query: query)
        let trimmed = Array(results.prefix(limit))
        let summaries = trimmed.map { summary(for: $0) }
        JSONOutput.success([
            "contacts": summaries,
            "total": results.count,
            "limit": limit,
            "hasMore": results.count > trimmed.count
        ] as [String: Any])
    }

    static func readContact(id: String) async {
        guard await requestAccess() else {
            JSONOutput.error("Contacts access denied. Grant access in System Settings > Privacy & Security > Contacts.")
            return
        }
        do {
            let contact = try store.unifiedContact(
                withIdentifier: id,
                keysToFetch: defaultKeys
            )
            JSONOutput.success(fullDetail(for: contact))
        } catch {
            JSONOutput.error("Contact not found: \(id)")
        }
    }

    // MARK: - Search

    // Runs name / email / phone predicates, then falls back to a digits-only
    // substring scan over every contact's phone numbers when the query looks
    // phone-ish (CNContact.predicateForContacts(matching: CNPhoneNumber) only
    // matches normalized full numbers — partials like "+4917" would otherwise
    // return empty). Deduplicated by identifier.
    private static func findMatches(query: String) -> [CNContact] {
        var seen = Set<String>()
        var results: [CNContact] = []
        for predicate in predicates(for: query) {
            do {
                let batch = try store.unifiedContacts(matching: predicate, keysToFetch: defaultKeys)
                for c in batch where !seen.contains(c.identifier) {
                    seen.insert(c.identifier)
                    results.append(c)
                }
            } catch {
                continue
            }
        }
        if looksLikePhone(query) {
            for c in phoneSubstringMatches(query: query) where !seen.contains(c.identifier) {
                seen.insert(c.identifier)
                results.append(c)
            }
        }
        return results
    }

    private static func predicates(for query: String) -> [NSPredicate] {
        var list: [NSPredicate] = [CNContact.predicateForContacts(matchingName: query)]
        if query.contains("@") {
            list.append(CNContact.predicateForContacts(matchingEmailAddress: query))
        }
        if looksLikePhone(query) {
            list.append(CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: query)))
        }
        return list
    }

    private static func looksLikePhone(_ query: String) -> Bool {
        query.first.map { "+0123456789".contains($0) } ?? false
    }

    private static func phoneSubstringMatches(query: String) -> [CNContact] {
        // Normalize to digits only, then also strip any leading zeros so that
        // national-format queries (e.g. trunk-prefixed local numbers) match
        // international-format stored phone numbers that omit the trunk digit.
        let digits = query.filter(\.isNumber)
        let trimmed = String(digits.drop(while: { $0 == "0" }))
        let candidates = Set([digits, trimmed].filter { $0.count >= 3 })
        guard !candidates.isEmpty else { return [] }

        let request = CNContactFetchRequest(keysToFetch: defaultKeys)
        request.unifyResults = true
        var results: [CNContact] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                for phone in contact.phoneNumbers {
                    let phoneDigits = phone.value.stringValue.filter(\.isNumber)
                    if candidates.contains(where: { phoneDigits.contains($0) }) {
                        results.append(contact)
                        return
                    }
                }
            }
        } catch {
            return results
        }
        return results
    }

    // MARK: - Shaping

    private static func summary(for c: CNContact) -> [String: Any] {
        [
            "id": c.identifier,
            "name": CNContactFormatter.string(from: c, style: .fullName) ?? "",
            "organization": c.organizationName,
            "emails": c.emailAddresses.map { $0.value as String },
            "phones": c.phoneNumbers.map { $0.value.stringValue }
        ]
    }

    private static func fullDetail(for c: CNContact) -> [String: Any] {
        var dict = summary(for: c)
        dict["givenName"] = c.givenName
        dict["middleName"] = c.middleName
        dict["familyName"] = c.familyName
        dict["nickname"] = c.nickname
        dict["jobTitle"] = c.jobTitle
        dict["emails"] = c.emailAddresses.map { labeled($0.label, $0.value as String) }
        dict["phones"] = c.phoneNumbers.map { labeled($0.label, $0.value.stringValue) }
        dict["addresses"] = c.postalAddresses.map { postalDict($0) }
        dict["urls"] = c.urlAddresses.map { labeled($0.label, $0.value as String) }
        if let bday = c.birthday, let date = Calendar(identifier: .gregorian).date(from: bday) {
            dict["birthday"] = ISO8601DateFormatter().string(from: date)
        }
        dict["hasImage"] = c.imageDataAvailable
        return dict
    }

    private static func labeled(_ label: String?, _ value: String) -> [String: Any] {
        var d: [String: Any] = ["value": value]
        if let l = label {
            d["label"] = CNLabeledValue<NSString>.localizedString(forLabel: l)
        }
        return d
    }

    private static func postalDict(_ entry: CNLabeledValue<CNPostalAddress>) -> [String: Any] {
        let a = entry.value
        return [
            "label": entry.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? "",
            "street": a.street,
            "city": a.city,
            "state": a.state,
            "postalCode": a.postalCode,
            "country": a.country
        ]
    }
}
