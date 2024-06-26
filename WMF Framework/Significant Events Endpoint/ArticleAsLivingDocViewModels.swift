
import Foundation

//tonitodo: It makes more sense for this to live in the app. Can we move out of WMF?

public struct ArticleAsLivingDocViewModel {
    
    public let nextRvStartId: UInt?
    public let sha: String?
    public let sections: [SectionHeader]
    public let articleInsertHtmlSnippets: [String]
    public let newChangesTimestamp: String?
    public let lastUpdatedTimestamp: String?
    public let summaryText: String?
    
    public init(nextRvStartId: UInt?, sha: String?, sections: [SectionHeader], summaryText: String?, articleInsertHtmlSnippets: [String], newChangesTimestamp: String?, lastUpdatedTimestamp: String?) {
        self.nextRvStartId = nextRvStartId
        self.sha = sha
        self.sections = sections
        self.summaryText = summaryText
        self.articleInsertHtmlSnippets = articleInsertHtmlSnippets
        self.newChangesTimestamp = newChangesTimestamp
        self.lastUpdatedTimestamp = lastUpdatedTimestamp
    }
    
    public init?(significantEvents: SignificantEvents) {
        
        guard let isoDateFormatter = DateFormatter.wmf_iso8601(),
              let dayMonthNumberYearDateFormatter = DateFormatter.wmf_monthNameDayOfMonthNumberYear() else {
            assertionFailure("Unable to generate date formatters for Significant Events View Models")
            return nil
        }
        
        self.nextRvStartId = significantEvents.nextRvStartId
        self.sha = significantEvents.sha
        
        //initialize summary text
        var summaryText: String? = nil
        if let earliestDate = isoDateFormatter.date(from: significantEvents.summary.earliestTimestampString) {
            
            let currentDate = Date()
            let calendar = NSCalendar.current
            let unitFlags:Set<Calendar.Component> = [.day]
            let components = calendar.dateComponents(unitFlags, from: earliestDate, to: currentDate)
            if let numberOfDays = components.day {
                summaryText = String.localizedStringWithFormat(CommonStrings.articleAsLivingDocSummaryTitle,
                                                                       significantEvents.summary.numChanges,
                                                                       significantEvents.summary.numUsers,
                                                                       numberOfDays)
            }
        }
        self.summaryText = summaryText
        
        // loop through typed events, turn into view models and segment off into sections
        var currentSectionEvents: [TypedEvent] = []
        var sections: [SectionHeader] = []
        
        var maybeCurrentTimestamp: Date?
        var maybePreviousTimestamp: Date?
        
        for originalEvent in significantEvents.typedEvents {
            
            var maybeEvent: TypedEvent? = nil
            if let smallEventViewModel = Event.Small(typedEvents: [originalEvent]) {
                maybeEvent = .small(smallEventViewModel)
            } else if let largeEventViewModel = Event.Large(typedEvent: originalEvent) {
                maybeEvent = .large(largeEventViewModel)
            }
            
            guard let event = maybeEvent else {
                assertionFailure("Unable to instantiate event view model, skipping event")
                continue
            }
                
            switch originalEvent {
            case .large(let largeChange):
                maybeCurrentTimestamp = isoDateFormatter.date(from: largeChange.timestampString)
            case .newTalkPageTopic(let newTalkPageTopic):
                maybeCurrentTimestamp = isoDateFormatter.date(from: newTalkPageTopic.timestampString)
            case .vandalismRevert(let vandalismRevert):
                maybeCurrentTimestamp = isoDateFormatter.date(from: vandalismRevert.timestampString)
            case .small(let smallChange):
                maybeCurrentTimestamp = isoDateFormatter.date(from: smallChange.timestampString)
            }
        
            guard let currentTimestamp = maybeCurrentTimestamp else {
                assertionFailure("Significant Events - Unable to determine event timestamp, skipping event.")
                continue
            }
            
            if let previousTimestamp = maybePreviousTimestamp {
                let calendar = NSCalendar.current
                if !calendar.isDate(previousTimestamp, inSameDayAs: currentTimestamp) {
                    //multiple days have passed since last event, package up current sections into new section
                    let section = SectionHeader(timestamp: previousTimestamp, typedEvents: currentSectionEvents, subtitleDateFormatter: dayMonthNumberYearDateFormatter)
                    sections.append(section)
                    currentSectionEvents.removeAll()
                    currentSectionEvents.append(event)
                    maybePreviousTimestamp = currentTimestamp
                } else {
                    currentSectionEvents.append(event)
                    maybePreviousTimestamp = currentTimestamp
                }
            } else {
                currentSectionEvents.append(event)
                maybePreviousTimestamp = currentTimestamp
            }
        }
    
        //capture any final currentSectionEvents into new section
        if let currentTimestamp = maybeCurrentTimestamp {
            let section = SectionHeader(timestamp: currentTimestamp, typedEvents: currentSectionEvents, subtitleDateFormatter: dayMonthNumberYearDateFormatter)
            sections.append(section)
            currentSectionEvents.removeAll()
        }
        
        //collapse sibling small event view models
        var finalSections: [SectionHeader] = []
        for section in sections {
            var collapsedEventViewModels: [TypedEvent] = []
            var currentSmallChanges: [SignificantEvents.Event.Small] = []
            for event in section.typedEvents {
                switch event {
                case .small(let smallEventViewModel):
                    currentSmallChanges.append(contentsOf: smallEventViewModel.smallChanges)
                default:
                    if currentSmallChanges.count > 0 {
                        
                        collapsedEventViewModels.append(.small(Event.Small(smallChanges: currentSmallChanges)))
                        currentSmallChanges.removeAll()
                    }
                    collapsedEventViewModels.append(event)
                    continue
                }
            }
            
            //add any final small changes
            if currentSmallChanges.count > 0 {
                collapsedEventViewModels.append(.small(Event.Small(smallChanges: currentSmallChanges)))
                currentSmallChanges.removeAll()
            }
            
            let collapsedSection = SectionHeader(timestamp: section.timestamp, typedEvents: collapsedEventViewModels, subtitleDateFormatter: dayMonthNumberYearDateFormatter)
            finalSections.append(collapsedSection)
        }
            
        self.sections = finalSections
        
        //grab first 3 large event html snippets
        var articleInsertHtmlSnippets: [String] = []
        var newChangesTimestamp: String?
        var lastUpdatedTimestamp: String?
        let htmlSnippetCountMax = 3
        
        outerLoop: for (sectionIndex, section) in finalSections.enumerated() {
            for (itemIndex, event) in section.typedEvents.enumerated() {
                switch event {
                case .small(let smallEvent):
                    if lastUpdatedTimestamp == nil {
                        lastUpdatedTimestamp = smallEvent.timestampForDisplay()
                    }
                case .large(let largeEvent):
                    if lastUpdatedTimestamp == nil {
                        lastUpdatedTimestamp = largeEvent.fullyRelativeTimestampForDisplay()
                    }
                    let indexPath = IndexPath(item: itemIndex, section: sectionIndex)
                    if let htmlSnippet = largeEvent.articleInsertHtmlSnippet(isFirst: articleInsertHtmlSnippets.count == 0, indexPath: indexPath) {
                        if articleInsertHtmlSnippets.count < htmlSnippetCountMax {
                            articleInsertHtmlSnippets.append(htmlSnippet)
                            if articleInsertHtmlSnippets.count == 1 {
                                newChangesTimestamp = largeEvent.fullyRelativeTimestampForDisplay()
                            }
                        } else {
                            if lastUpdatedTimestamp != nil {
                                break outerLoop
                            }
                        }
                    }
                }
            }
        }
        
        self.articleInsertHtmlSnippets = articleInsertHtmlSnippets
        self.newChangesTimestamp = newChangesTimestamp
        self.lastUpdatedTimestamp = lastUpdatedTimestamp
    }
    
    static func displayTimestamp(timestampString: String, fullyRelative: Bool) -> String? {
        if let isoDateFormatter = DateFormatter.wmf_iso8601(),
           let timeDateFormatter = DateFormatter.wmf_24hshortTimeWithUTCTimeZone(),
           let date = isoDateFormatter.date(from: timestampString) {
            if fullyRelative {
                let relativeTime = (date as NSDate).wmf_fullyLocalizedRelativeDateStringFromLocalDateToNow()
                return relativeTime
            } else {
                let calendar = NSCalendar.current
                let unitFlags:Set<Calendar.Component> = [.day]
                let components = calendar.dateComponents(unitFlags, from: date, to: Date())
                if let numberOfDays = components.day {
                    switch numberOfDays {
                    case 0:
                        let relativeTime = (date as NSDate).wmf_fullyLocalizedRelativeDateStringFromLocalDateToNow()
                        return relativeTime
                    default:
                        let shortTime = timeDateFormatter.string(from: date)
                        return shortTime
                    }
                }
            }
        }
        
        return nil
    }
}

//MARK: SectionHeader

public extension ArticleAsLivingDocViewModel {
    
    class SectionHeader: Hashable {
        public let title: String
        public let subtitleTimestampDisplay: String
        public let timestamp: Date
        public let typedEvents: [TypedEvent]
        init(timestamp: Date, typedEvents: [TypedEvent], subtitleDateFormatter: DateFormatter) {
            let nsTimestamp = timestamp as NSDate
            self.title = nsTimestamp.wmf_isTodayUTC()
                ? nsTimestamp.wmf_localizedRelativeDateFromMidnightUTCDate()
                : nsTimestamp.wmf_localizedRelativeDateStringFromLocalDate(toLocalDate: Date())
            self.subtitleTimestampDisplay = subtitleDateFormatter.string(from: timestamp)
            self.timestamp = timestamp
            self.typedEvents = typedEvents
        }
        
        public static func == (lhs: ArticleAsLivingDocViewModel.SectionHeader, rhs: ArticleAsLivingDocViewModel.SectionHeader) -> Bool {
            return lhs.subtitleTimestampDisplay == rhs.subtitleTimestampDisplay
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(subtitleTimestampDisplay)
        }
    }
}

//MARK: Events

public extension ArticleAsLivingDocViewModel {
    
    enum TypedEvent: Hashable {
        case small(Event.Small)
        case large(Event.Large)
        
        public static func == (lhs: ArticleAsLivingDocViewModel.TypedEvent, rhs: ArticleAsLivingDocViewModel.TypedEvent) -> Bool {
            switch lhs {
            case .large(let leftLargeEvent):
                switch rhs {
                case .large(let rightLargeEvent):
                    return leftLargeEvent == rightLargeEvent
                default:
                    return false
                }
            case .small(let leftSmallEvent):
                switch rhs {
                case .small(let rightSmallEvent):
                    return leftSmallEvent == rightSmallEvent
                default:
                    return false
                }
            
            }
        }
        
        public func hash(into hasher: inout Hasher) {
            switch self {
            case .small(let smallEvent):
                smallEvent.smallChanges.forEach { hasher.combine($0.revId) }
            case .large(let largeEvent):
                hasher.combine(largeEvent.revId)
            }
        }
    }
}

public extension ArticleAsLivingDocViewModel {
    
    struct Event {
        
        public class Small: Equatable {
            
            public private(set) var eventDescription: NSAttributedString?
            private var lastTraitCollection: UITraitCollection?
            public let smallChanges: [SignificantEvents.Event.Small]
            
            init?(typedEvents: [SignificantEvents.TypedEvent]) {
                
                var smallChanges: [SignificantEvents.Event.Small] = []
                for event in typedEvents {
                    switch event {
                    case .small(let smallChange):
                        smallChanges.append(smallChange)
                    default:
                        return nil
                    }
                }
                
                guard smallChanges.count > 0 else {
                    return nil
                }
                
                self.smallChanges = smallChanges
            }
            
            init(smallChanges: [SignificantEvents.Event.Small]) {
                self.smallChanges = smallChanges
            }
            
            public static func == (lhs: ArticleAsLivingDocViewModel.Event.Small, rhs: ArticleAsLivingDocViewModel.Event.Small) -> Bool {
                return lhs.smallChanges == rhs.smallChanges
            }
            
            //Only used in the html portion of the feature
            func timestampForDisplay() -> String? {
                
                guard let timestampString = smallChanges.first?.timestampString else {
                    return nil
                }
                
                let displayTimestamp = ArticleAsLivingDocViewModel.displayTimestamp(timestampString: timestampString, fullyRelative: true)
                
                return displayTimestamp
            }
        }
        
        public class Large: Equatable {
            
            public enum ChangeDetail {
                case snippet(Snippet) //use for a basic horizontally scrolling snippet cell (will contain talk page topic snippets, added text snippets, article description updated snippets)
                case reference(Reference)
            }
            
            public struct Snippet {
                public let displayText: NSAttributedString
            }
            
            public struct Reference {
                public let type: String
                public let description: NSAttributedString
                public let accessDateYearDisplay: String?
            }
            
            enum UserType {
                case standard
                case anonymous
                case bot
            }
            
            public enum ButtonsToDisplay {
                case thankAndViewChanges(userId: UInt, revisionId: UInt)
                case viewDiscussion(sectionName: String)
            }

            static let editCountFormatter: NumberFormatter = {
                let numberFormatter = NumberFormatter()
                numberFormatter.usesGroupingSeparator = true
                numberFormatter.numberStyle = .decimal
                return numberFormatter
            }()

            private let typedEvent: SignificantEvents.TypedEvent
            private(set) var eventDescription: NSAttributedString?
            private(set) var changeDetails: [ChangeDetail]?
            private(set) var displayTimestamp: String?
            private(set) var userInfo: NSAttributedString?
            let userId: UInt
            let userType: UserType
            public let buttonsToDisplay: ButtonsToDisplay
            private var lastTraitCollection: UITraitCollection?
            public var revId: UInt = 0
            
            init?(typedEvent: SignificantEvents.TypedEvent) {
                
                let userGroups: [String]?
                switch typedEvent {
                case .newTalkPageTopic(let newTalkPageTopic):
                    self.userId = newTalkPageTopic.userId
                    userGroups = newTalkPageTopic.userGroups
                    self.buttonsToDisplay = .viewDiscussion(sectionName: newTalkPageTopic.section)
                case .large(let largeChange):
                    self.userId = largeChange.userId
                    userGroups = largeChange.userGroups
                    self.buttonsToDisplay = .thankAndViewChanges(userId: largeChange.userId, revisionId: largeChange.revId)
                case .vandalismRevert(let vandalismRevert):
                    self.userId = vandalismRevert.userId
                    userGroups = vandalismRevert.userGroups
                    self.buttonsToDisplay = .thankAndViewChanges(userId: vandalismRevert.userId, revisionId: vandalismRevert.revId)
                case .small:
                    return nil
                }
                
                if let userGroups = userGroups,
                   userGroups.contains("bot") {
                    userType = .bot
                } else if self.userId == 0 {
                    userType = .anonymous
                } else {
                    userType = .standard
                }
                
                self.typedEvent = typedEvent
                switch typedEvent {
                case .large(let largeChange):
                    revId = largeChange.revId
                case .newTalkPageTopic(let newTalkPageTopic):
                    revId = newTalkPageTopic.revId
                case .vandalismRevert(let vandalismRevert):
                    revId = vandalismRevert.revId
                default:
                    assertionFailure("Shouldn't happen")
                }
                
            }
            
            public convenience init?(forPrototypeText prototypeText: String) {
                let originalUntypedEvent = SignificantEvents.UntypedEvent(forPrototypeText: prototypeText)
                guard let originalLargeChange = SignificantEvents.Event.Large(untypedEvent: originalUntypedEvent) else {
                    return nil
                }
                let originalTypedEvent = SignificantEvents.TypedEvent.large(originalLargeChange)
                self.init(typedEvent: originalTypedEvent)
            }
            
            public static func == (lhs: ArticleAsLivingDocViewModel.Event.Large, rhs: ArticleAsLivingDocViewModel.Event.Large) -> Bool {
                return lhs.revId == rhs.revId
            }
            
        }

    }
}

//MARK: Small Event Type Helper methods

public extension ArticleAsLivingDocViewModel.Event.Small {
    
    func eventDescriptionForTraitCollection(_ traitCollection: UITraitCollection, theme: Theme) -> NSAttributedString {
        if let lastTraitCollection = lastTraitCollection,
           let eventDescription = eventDescription {
            if lastTraitCollection == traitCollection {
                return eventDescription
            }
        }
        
        let font = UIFont.wmf_font(.italicSubheadline, compatibleWithTraitCollection: traitCollection)
        let attributes = [NSAttributedString.Key.font: font,
                          NSAttributedString.Key.foregroundColor: theme.colors.primaryText]
        
        let localizedString = String.localizedStringWithFormat(
            CommonStrings.smallChangeDescription,
            smallChanges.count)
        
        let eventDescription = NSAttributedString(string: localizedString, attributes: attributes)
        
        self.lastTraitCollection = traitCollection
        self.eventDescription = eventDescription
        return eventDescription
    }
}

//MARK: Large Event Type Helper methods

public extension ArticleAsLivingDocViewModel.Event.Large {
    
    func firstSnippetFromPrototypeModel(traitCollection: UITraitCollection, theme: Theme) -> NSAttributedString? {
        let changeDetails = changeDetailsForTraitCollection(traitCollection, theme: theme)
        if changeDetails.count > 0 {
            let firstChangeDetail = changeDetails[0]
            switch firstChangeDetail {
            case .snippet(let snippet):
                return snippet.displayText
            default:
                return nil
            }
        }
        
        return nil
    }
    
    func articleInsertHtmlSnippet(isFirst: Bool = false, indexPath: IndexPath) -> String? {
        guard let timestampForDisplay = self.fullyRelativeTimestampForDisplay(),
              let eventDescription = eventDescriptionHtmlSnippet(indexPath: indexPath),
              let userInfo = userInfoHtmlSnippet() else {
            return nil
        }
        
        let liElementIdName = isFirst ? "significant-changes-first-list" : "significant-changes-list"
        
        return "<li id='\(liElementIdName)'><p class='significant-changes-timestamp'>\(timestampForDisplay)</p><p class='significant-changes-description'>\(eventDescription)</p><p class='significant-changes-userInfo'>\(userInfo)</p></li>"
    }
    
    private func htmlSignificantEventsLinkOpeningTagForIndexPath(_ indexPath: IndexPath) -> String {
        return "<a href='#significant-events-\(indexPath.item)-\(indexPath.section)'>"
    }
    
    private var htmlSignificantEventsLinkEndingTag: String {
        return "</a>"
    }
    
    private func eventDescriptionHtmlSnippet(indexPath: IndexPath) -> String? {
        
        let sections = sectionsSet()
        let sectionsHtml = localizedSectionHtmlSnippet(sectionsSet: sections)
        
        let eventDescription: String
        switch typedEvent {
        case .newTalkPageTopic:
            let discussionText = htmlSignificantEventsLinkOpeningTagForIndexPath(indexPath) + CommonStrings.newTalkTopicDiscussion + htmlSignificantEventsLinkEndingTag
            eventDescription = String.localizedStringWithFormat(CommonStrings.newTalkTopicDescriptionFormat, discussionText)
        case .vandalismRevert:
            let event = htmlSignificantEventsLinkOpeningTagForIndexPath(indexPath) + CommonStrings.vandalismRevertDescription + htmlSignificantEventsLinkEndingTag
            if let sectionsHtml = sectionsHtml {
                eventDescription = event + sectionsHtml
            } else {
                eventDescription = event
            }
        case .large(let largeChange):
            
            guard let mergedDescription = mergedDescriptionForTypedChanges(largeChange.typedChanges, htmlInsertIndexPath: indexPath) else {
                assertionFailure("This should not happen")
                return nil
            }
            
            if let sectionsHtml = sectionsHtml {
                eventDescription = mergedDescription + sectionsHtml
            } else {
                eventDescription = mergedDescription
            }
            
        case .small:
            assertionFailure("This should not happen")
            return nil
        }
        
        return eventDescription
    }
    
    private func mergedDescriptionForTypedChanges(_ changes: [SignificantEvents.TypedChange], htmlInsertIndexPath: IndexPath?) -> String? {
        
        let individualDescriptions = self.individualDescriptionsForTypedChanges(changes)
        let sortedDescriptions = individualDescriptions.sorted { $0.priority < $1.priority }
        
        // Slightly different logic when creating this for the article content html insert.
        // We need to wrap individual descriptions into links, and condense multiple changes into "Multiple changes made" link.
        
        if let htmlInsertIndexPath = htmlInsertIndexPath {
            switch sortedDescriptions.count {
            case 0:
                assertionFailure("This should not happen")
                return nil
            case 1:
                let description = sortedDescriptions[0].text
                return htmlSignificantEventsLinkOpeningTagForIndexPath(htmlInsertIndexPath) + description + htmlSignificantEventsLinkEndingTag
            default:
                return htmlSignificantEventsLinkOpeningTagForIndexPath(htmlInsertIndexPath) + CommonStrings.multipleChangesMadeDescription + htmlSignificantEventsLinkEndingTag
            }
        }
        
        if #available(iOSApplicationExtension 13.0, *) {
            let mergedDescription = ListFormatter.localizedString(byJoining: sortedDescriptions.map { $0.text })
            return mergedDescription.isEmpty ? nil : mergedDescription
        } else {
            return nil
        }
    }
    
    func eventDescriptionForTraitCollection(_ traitCollection: UITraitCollection, theme: Theme) -> NSAttributedString {
        
        let sections = sectionsSet()
        let sectionsAttributedString = localizedSectionAttributedString(sectionsSet: sections, traitCollection: traitCollection, theme: theme)
        
        if let lastTraitCollection = lastTraitCollection,
           let eventDescription = eventDescription {
            if lastTraitCollection == traitCollection {
                return eventDescription
            }
        }
        
        let font = UIFont.wmf_font(.body, compatibleWithTraitCollection: traitCollection)
        let attributes = [NSAttributedString.Key.font: font,
                          NSAttributedString.Key.foregroundColor: theme.colors.primaryText]
        
        let eventDescriptionMutableAttributedString: NSMutableAttributedString = NSMutableAttributedString(string: "")
        switch typedEvent {
        case .newTalkPageTopic:
            let localizedString = String.localizedStringWithFormat(CommonStrings.newTalkTopicDescriptionFormat, CommonStrings.newTalkTopicDiscussion)
            let eventAttributedString = NSAttributedString(string: localizedString, attributes: attributes)
            eventDescriptionMutableAttributedString.append(eventAttributedString)
            
        case .vandalismRevert:
            
            let event = CommonStrings.vandalismRevertDescription
            
            let eventAttributedString = NSAttributedString(string: event, attributes: attributes)
            eventDescriptionMutableAttributedString.append(eventAttributedString)
        
        case .large(let largeChange):
            
            guard let mergedDescription = mergedDescriptionForTypedChanges(largeChange.typedChanges, htmlInsertIndexPath: nil) else {
                assertionFailure("This should not happen")
                break
            }
            
            let mergedDescriptionAttributedString = NSAttributedString(string: mergedDescription, attributes: attributes)
            eventDescriptionMutableAttributedString.append(mergedDescriptionAttributedString)
            
        case .small:
            assertionFailure("Unexpected timeline event type")
            break
        }
        
        if let sectionsAttributedString = sectionsAttributedString {
            eventDescriptionMutableAttributedString.append(sectionsAttributedString)
        }
        
        guard let finalEventAttributedString = eventDescriptionMutableAttributedString.copy() as? NSAttributedString else {
            assertionFailure("This should not happen")
            let empty = NSAttributedString(string: "")
            eventDescription = empty
            self.lastTraitCollection = traitCollection
            return empty
        }
        
        eventDescription = finalEventAttributedString
        self.lastTraitCollection = traitCollection
        return finalEventAttributedString
    }
    
    struct IndividualDescription {
        let priority: Int //used for sorting
        let text: String
    }
    
    private func individualDescriptionsForTypedChanges(_ typedChanges: [SignificantEvents.TypedChange]) -> [IndividualDescription] {
        
        var descriptions: [IndividualDescription] = []
        var numReferences = 0
        for typedChange in typedChanges {
            switch typedChange {
            case .addedText(let addedText):
                let description = String.localizedStringWithFormat(CommonStrings.addedTextDescription, addedText.characterCount)
                descriptions.append(IndividualDescription(priority: 1, text: description))
            case .deletedText(let deletedText):
                let description = String.localizedStringWithFormat(CommonStrings.deletedTextDescription, deletedText.characterCount)
                descriptions.append(IndividualDescription(priority: 2, text: description))
            case .newTemplate(let newTemplate):
                var numArticleDescriptions = 0
                for template in newTemplate.typedTemplates {
                    switch template {
                    case .articleDescription:
                        numArticleDescriptions += 1
                    case .bookCitation,
                         .journalCitation,
                         .newsCitation,
                         .websiteCitation:
                        numReferences += 1
                    }
                }
                
                if numArticleDescriptions > 0 {
                    let description = CommonStrings.articleDescriptionUpdatedDescription
                    descriptions.append(IndividualDescription(priority: 3, text: description))
                }
            }
        }
        
        if descriptions.count == 0 {
            switch numReferences {
            case 0:
                break
            case 1:
                let description = CommonStrings.singleReferenceAddedDescription
                descriptions.append(IndividualDescription(priority: 0, text: description))
            default:
                let description = CommonStrings.multipleReferencesAddedDescription
                descriptions.append(IndividualDescription(priority: 0, text: description))
            }
        } else {
            if numReferences > 0 {
                let description = String.localizedStringWithFormat(CommonStrings.numericalMultipleReferencesAddedDescription, numReferences)
                descriptions.append(IndividualDescription(priority: 0, text: description))
            }
        }
        
        return descriptions
    }
    
    private func sectionsSet() -> Set<String> {
        let set: Set<String>
        switch typedEvent {
        case .newTalkPageTopic:
            set = Set<String>()
        case .vandalismRevert(let vandalismRevert):
            set = Set(vandalismRevert.sections)
        case .large(let largeChange):
            var sections: [String] = []
            for typedChange in largeChange.typedChanges {
                switch typedChange {
                case .addedText(let addedTextChange):
                    sections.append(contentsOf: addedTextChange.sections)
                case .deletedText(let deletedTextChange):
                    sections.append(contentsOf: deletedTextChange.sections)
                case .newTemplate(let newTemplate):
                    sections.append(contentsOf: newTemplate.sections)
                }
            }
            
            set = Set(sections)
        case .small:
            assertionFailure("This shouldn't happen")
            set = Set<String>()
        }
        
        //strip == signs from all section titles
        let finalSet = set.map { (section) -> String in
            if let match = section.range(of: "(?<==)[^=]+", options: .regularExpression) {
                return String(section[match])
            }
            
            return section
        }
        
        return Set(finalSet)
    }
    
    private func localizedStringFromSections(sections: [String]) -> String? {
        var localizedString: String
        switch sections.count {
        case 0:
            return nil
        case 1:
            let firstSection = sections[0]
            localizedString = String.localizedStringWithFormat(CommonStrings.oneSectionDescription, firstSection)
        case 2:
            let firstSection = sections[0]
            let secondSection = sections[1]
            localizedString = String.localizedStringWithFormat(CommonStrings.twoSectionsDescription, firstSection, secondSection)
        default:
            localizedString = String.localizedStringWithFormat(CommonStrings.manySectionsDescription, sections.count)
        }
        
        return " " + localizedString
    }
    
    private func localizedSectionHtmlSnippet(sectionsSet: Set<String>) -> String? {
        
        let sections = Array(sectionsSet)
        guard let localizedString = localizedStringFromSections(sections: sections) else {
            return nil
        }
        
        let mutableLocalizedString = NSMutableString(string: localizedString)

        var ranges: [NSRange] = []
        for section in sections {
            let rangeOfSection = (localizedString as NSString).range(of: section)
            let rangeValid = rangeOfSection.location != NSNotFound && rangeOfSection.location + rangeOfSection.length <= localizedString.count
            if rangeValid {
                ranges.append(rangeOfSection)
            }
        }

        var offset = 0
        for range in ranges {
            let italicStart = "<i>"
            let italicEnd = "</i>"
            mutableLocalizedString.insert(italicStart, at: range.location + offset)
            offset += italicStart.count
            mutableLocalizedString.insert(italicEnd, at: range.location + range.length + offset)
            offset += italicEnd.count
        }
        
        if let returnString = mutableLocalizedString.copy() as? NSString {
            return returnString as String
        } else {
            assertionFailure("This shouldn't happen")
            return nil
        }
    }
    
    private func localizedSectionAttributedString(sectionsSet: Set<String>, traitCollection: UITraitCollection, theme: Theme) -> NSAttributedString? {
        let sections = Array(sectionsSet)
        guard let localizedString = localizedStringFromSections(sections: sections) else {
            return nil
        }
        
        let font = UIFont.wmf_font(.body, compatibleWithTraitCollection: traitCollection)
        let italicFont = UIFont.wmf_font(.italicBody, compatibleWithTraitCollection: traitCollection)
        let attributes = [NSAttributedString.Key.font: font,
                          NSAttributedString.Key.foregroundColor: theme.colors.primaryText]
        
        var ranges: [NSRange] = []
        for section in sections {
            let rangeOfSection = (localizedString as NSString).range(of: section)
            let rangeValid = rangeOfSection.location != NSNotFound && rangeOfSection.location + rangeOfSection.length <= localizedString.count
            if rangeValid {
                ranges.append(rangeOfSection)
            }
        }
        
        let mutableAttributedString = NSMutableAttributedString(string: localizedString, attributes: attributes)
        
        for range in ranges {
            mutableAttributedString.addAttribute(NSAttributedString.Key.font, value: italicFont, range: range)
        }
        
        guard let attributedString = mutableAttributedString.copy() as? NSAttributedString else {
            assertionFailure("This shouldn't happen")
            return NSAttributedString(string: localizedString, attributes: attributes)
        }
        
        return attributedString
    }
    
    func changeDetailsForTraitCollection(_ traitCollection: UITraitCollection, theme: Theme) -> [ChangeDetail] {
        if let lastTraitCollection = lastTraitCollection,
           let changeDetails = changeDetails {
            if lastTraitCollection == traitCollection {
                return changeDetails
            }
        }
        
        var changeDetails: [ChangeDetail] = []
        
        switch typedEvent {
        case .newTalkPageTopic(let newTalkPageTopic):
            let attributedString = newTalkPageTopic.snippet.byAttributingHTML(with: .subheadline, boldWeight: .regular, matching: traitCollection, color: theme.colors.primaryText, linkColor: theme.colors.link, handlingLists: true, handlingSuperSubscripts: true)
            let changeDetail = ChangeDetail.snippet(Snippet(displayText: attributedString))
            changeDetails.append(changeDetail)
        case .large(let largeChange):
            for typedChange in largeChange.typedChanges {
                switch typedChange {
                case .addedText(let addedText):
                    //TODO: Add highlighting here. For snippetType 1, add a highlighting attribute across the whole string. Otherwise, seek out highlight-add span ranges and add those attributes
                    guard let snippet = addedText.snippet else {
                        continue
                    }
                    
                    let attributedString = snippet.byAttributingHTML(with: .subheadline, boldWeight: .regular, matching: traitCollection, color: theme.colors.primaryText, handlingLinks: true, linkColor: theme.colors.link, handlingLists: true, handlingSuperSubscripts: true)
                    let changeDetail = ChangeDetail.snippet(Snippet(displayText: attributedString))
                    changeDetails.append(changeDetail)
                case .deletedText:
                    continue;
                case .newTemplate(let newTemplate):
                    for template in newTemplate.typedTemplates {
                        
                        switch template {
                        case .articleDescription(let articleDescription):
                            let font = UIFont.wmf_font(.subheadline, compatibleWithTraitCollection: traitCollection)
                            let attributes = [NSAttributedString.Key.font: font,
                                              NSAttributedString.Key.foregroundColor:
                                                theme.colors.primaryText]
                            let attributedString = NSAttributedString(string: articleDescription.text, attributes: attributes)
                            let changeDetail = ChangeDetail.snippet(Snippet(displayText: attributedString))
                            changeDetails.append(changeDetail)
                            //tonitodo: these code blocks are all very similar. make a generic method instead?
                        case .bookCitation(let bookCitation):
                            let typeText = referenceTypeForTemplate(template, traitCollection: traitCollection, theme: theme)
                            let accessYear = accessDateYearForTemplate(template, traitCollection: traitCollection, theme: theme)
                            let bookCitationDescription = descriptionForBookCitation(bookCitation, traitCollection: traitCollection, theme: theme)
                            let reference = Reference(type: typeText, description: bookCitationDescription, accessDateYearDisplay: accessYear)
                            let changeDetail = ChangeDetail.reference(reference)
                            changeDetails.append(changeDetail)
                        case .journalCitation(let journalCitation):
                            let typeText = referenceTypeForTemplate(template, traitCollection: traitCollection, theme: theme)
                            let accessYear = accessDateYearForTemplate(template, traitCollection: traitCollection, theme: theme)
                            let citationDescription = descriptionForJournalCitation(journalCitation, traitCollection: traitCollection, theme: theme)
                            let reference = Reference(type: typeText, description: citationDescription, accessDateYearDisplay: accessYear)
                            let changeDetail = ChangeDetail.reference(reference)
                            changeDetails.append(changeDetail)
                        case .newsCitation(let newsCitation):
                            let typeText = referenceTypeForTemplate(template, traitCollection: traitCollection, theme: theme)
                            let accessYear = accessDateYearForTemplate(template, traitCollection: traitCollection, theme: theme)
                            let citationDescription = descriptionForNewsCitation(newsCitation, traitCollection: traitCollection, theme: theme)
                            let reference = Reference(type: typeText, description: citationDescription, accessDateYearDisplay: accessYear)
                            let changeDetail = ChangeDetail.reference(reference)
                            changeDetails.append(changeDetail)
                        case .websiteCitation(let websiteCitation):
                            let typeText = referenceTypeForTemplate(template, traitCollection: traitCollection, theme: theme)
                            let accessYear = accessDateYearForTemplate(template, traitCollection: traitCollection, theme: theme)
                            let citationDescription = descriptionForWebsiteCitation(websiteCitation, traitCollection: traitCollection, theme: theme)
                            let reference = Reference(type: typeText, description: citationDescription, accessDateYearDisplay: accessYear)
                            let changeDetail = ChangeDetail.reference(reference)
                            changeDetails.append(changeDetail)
                        }
                    }
                }
            }
        case .vandalismRevert:
            return []
        case .small:
            assertionFailure("This should not happen")
            return []
        }
        
        self.lastTraitCollection = traitCollection
        self.changeDetails = changeDetails
        return changeDetails
    }
    
    private func referenceTypeForTemplate(_ template: SignificantEvents.Template, traitCollection: UITraitCollection, theme: Theme) -> String {
        
        var typeString: String
        switch template {
        case .articleDescription:
            assertionFailure("This should not happen")
            return ""
        case .bookCitation:
            typeString = CommonStrings.newBookReferenceTitle
        case .journalCitation:
            typeString = CommonStrings.newJournalReferenceTitle
        case .newsCitation:
            typeString = CommonStrings.newNewsReferenceTitle
        case .websiteCitation:
            typeString = CommonStrings.newWebsiteReferenceTitle
            
        }
        
        return typeString
    }
    
    private func accessDateYearForTemplate(_ template: SignificantEvents.Template, traitCollection: UITraitCollection, theme: Theme) -> String? {
        
        let accessDateString: String?
        switch template {
        case .newsCitation(let newsCitation):
            accessDateString = newsCitation.accessDateString
        case .websiteCitation(let websiteCitation):
            accessDateString = websiteCitation.accessDateString
        default:
            return nil
        }
        
        if let accessDateString = accessDateString {
            let dateFormatter = DateFormatter.wmf_monthNameDayOfMonthNumberYear()
            if let date = dateFormatter?.date(from: accessDateString) {
                let yearDateFormatter = DateFormatter.wmf_year()
                let year = yearDateFormatter?.string(from: date)
                return year
            }
        }
        
        return nil
        
    }
    
    private func descriptionForJournalCitation(_ journalCitation: SignificantEvents.Citation.Journal, traitCollection: UITraitCollection, theme: Theme) -> NSAttributedString {
        
        let font = UIFont.wmf_font(.subheadline, compatibleWithTraitCollection: traitCollection)
        let boldFont = UIFont.wmf_font(.italicSubheadline, compatibleWithTraitCollection: traitCollection)
        let attributes = [NSAttributedString.Key.font: font,
                          NSAttributedString.Key.foregroundColor:
                            theme.colors.primaryText]
        let boldAttributes = [NSAttributedString.Key.font: boldFont,
                          NSAttributedString.Key.foregroundColor:
                            theme.colors.primaryText]
        
        let titleAttributedString: NSAttributedString
        let titleString = "\"\(journalCitation.title)\""
        let range = NSRange(location: 0, length: titleString.count)
        let mutableAttributedString = NSMutableAttributedString(string: titleString, attributes: attributes)
        if let urlString = journalCitation.urlString,
           let url = URL(string: urlString) {
            
                mutableAttributedString.addAttributes([NSAttributedString.Key.link : url,
                                             NSAttributedString.Key.foregroundColor: theme.colors.link], range: range)
        } else {
            mutableAttributedString.addAttributes(attributes, range: range)
        }
        
        titleAttributedString = mutableAttributedString.copy() as? NSAttributedString ?? NSAttributedString(string: "")
        
        var descriptionStart = ""
        if let firstName = journalCitation.firstName {
            if let lastName = journalCitation.lastName {
                descriptionStart += "\(lastName), \(firstName)"
            }
        } else {
            if let lastName = journalCitation.lastName {
                descriptionStart += "\(lastName)"
            }
        }
         
        if let sourceDate = journalCitation.sourceDateString {
            descriptionStart += "(\(sourceDate)). "
        } else {
            descriptionStart += ". "
        }
        
        let descriptionStartAttributedString = NSAttributedString(string: descriptionStart, attributes: attributes)
        
        var volumeString = ""
        if let volumeNumber = journalCitation.volumeNumber {
            volumeString = String.localizedStringWithFormat(CommonStrings.newJournalReferenceVolume, volumeNumber)
        }
        let volumeAttributedString = NSAttributedString(string: volumeString, attributes: boldAttributes)
        
        var descriptionEnd = ""
        if let database = journalCitation.database {
            let viaDatabaseString = String.localizedStringWithFormat(CommonStrings.newJournalReferenceDatabase, database)
            if let pages = journalCitation.pages {
                descriptionEnd += "\(pages) - \(viaDatabaseString). "
            } else {
                descriptionEnd += "\(viaDatabaseString). "
            }
        } else {
            if let pages = journalCitation.pages {
                descriptionEnd += "\(pages)."
            }
        }
        
        let descriptionEndAttributedString = NSAttributedString(string: descriptionEnd, attributes: attributes)

        
        let finalMutableAttributedString = NSMutableAttributedString(string: "")
        finalMutableAttributedString.append(descriptionStartAttributedString)
        finalMutableAttributedString.append(titleAttributedString)
        finalMutableAttributedString.append(volumeAttributedString)
        finalMutableAttributedString.append(descriptionEndAttributedString)
        
        return finalMutableAttributedString.copy() as? NSAttributedString ?? NSAttributedString(string: "")
        
    }
    
    private func descriptionForWebsiteCitation(_ websiteCitation: SignificantEvents.Citation.Website, traitCollection: UITraitCollection, theme: Theme) -> NSAttributedString {
        let font = UIFont.wmf_font(.subheadline, compatibleWithTraitCollection: traitCollection)
        let italicFont = UIFont.wmf_font(.italicSubheadline, compatibleWithTraitCollection: traitCollection)
        let attributes = [NSAttributedString.Key.font: font,
                          NSAttributedString.Key.foregroundColor:
                            theme.colors.primaryText]
        let italicAttributes = [NSAttributedString.Key.font: italicFont,
                          NSAttributedString.Key.foregroundColor:
                            theme.colors.primaryText]
        
        let titleAttributedString: NSAttributedString
        let titleString = "\"\(websiteCitation.title)\""
        let range = NSRange(location: 0, length: titleString.count)
        let mutableAttributedString = NSMutableAttributedString(string: titleString, attributes: attributes)
        let urlString = websiteCitation.urlString
        if let url = URL(string: urlString) {
            
                mutableAttributedString.addAttributes([NSAttributedString.Key.link : url,
                                             NSAttributedString.Key.foregroundColor: theme.colors.link], range: range)
        } else {
            mutableAttributedString.addAttributes(attributes, range: range)
        }
        
        titleAttributedString = mutableAttributedString.copy() as? NSAttributedString ?? NSAttributedString(string: "")
        
        var publisherText = ""
        if let publisher = websiteCitation.publisher {
            publisherText = "\(publisher). "
        }
        
        let publisherAttributedString = NSAttributedString(string: publisherText, attributes: italicAttributes)
        
        var accessDateString = ""
        if let accessDate = websiteCitation.accessDateString {
            accessDateString = "\(accessDate). "
        }
        
        let accessDateAttributedString = NSAttributedString(string: accessDateString, attributes: attributes)
        
        let finalMutableAttributedString = NSMutableAttributedString(string: "")
        finalMutableAttributedString.append(titleAttributedString)
        finalMutableAttributedString.append(publisherAttributedString)
        finalMutableAttributedString.append(accessDateAttributedString)
        
        if let archiveDateString = websiteCitation.archiveDateString,
           let archiveUrlString = websiteCitation.archiveDotOrgUrlString,
           let archiveUrl = URL(string: archiveUrlString) {
            let archiveLinkText = CommonStrings.newWebsiteReferenceArchiveUrlText
            let range = NSRange(location: 0, length: archiveLinkText.count)
            let archiveLinkMutableAttributedString = NSMutableAttributedString(string: titleString, attributes: attributes)
            archiveLinkMutableAttributedString.addAttributes([NSAttributedString.Key.link : archiveUrl,
                                         NSAttributedString.Key.foregroundColor: theme.colors.link], range: range)
            
            if let archiveLinkAttributedString = archiveLinkMutableAttributedString.copy() as? NSAttributedString {
                
                let lastText =  String.localizedStringWithFormat(CommonStrings.newWebsiteReferenceArchiveDateText, archiveDateString)
                
                let lastAttributedString = NSAttributedString(string: lastText, attributes: attributes)
                
                finalMutableAttributedString.append(archiveLinkAttributedString)
                finalMutableAttributedString.append(lastAttributedString)
                
            }
            
        }
        
        return finalMutableAttributedString.copy() as? NSAttributedString ?? NSAttributedString(string: "")
    }
    
    private func descriptionForNewsCitation(_ newsCitation: SignificantEvents.Citation.News, traitCollection: UITraitCollection, theme: Theme) -> NSAttributedString {
        
        let font = UIFont.wmf_font(.subheadline, compatibleWithTraitCollection: traitCollection)
        let italicFont = UIFont.wmf_font(.italicSubheadline, compatibleWithTraitCollection: traitCollection)
        let attributes = [NSAttributedString.Key.font: font,
                          NSAttributedString.Key.foregroundColor:
                            theme.colors.primaryText]
        let italicAttributes = [NSAttributedString.Key.font: italicFont,
                          NSAttributedString.Key.foregroundColor:
                            theme.colors.primaryText]
        
        let titleAttributedString: NSAttributedString
        let titleString = "\"\(newsCitation.title)\""
        let range = NSRange(location: 0, length: titleString.count)
        let mutableAttributedString = NSMutableAttributedString(string: titleString, attributes: attributes)
        if let urlString = newsCitation.urlString,
           let url = URL(string: urlString) {
            
                mutableAttributedString.addAttributes([NSAttributedString.Key.link : url,
                                             NSAttributedString.Key.foregroundColor: theme.colors.link], range: range)
        } else {
            mutableAttributedString.addAttributes(attributes, range: range)
        }
        
        titleAttributedString = mutableAttributedString.copy() as? NSAttributedString ?? NSAttributedString(string: "")
        
        var descriptionStart = ""
        if let firstName = newsCitation.firstName {
            if let lastName = newsCitation.lastName {
                descriptionStart += "\(lastName), \(firstName)"
            }
        } else {
            if let lastName = newsCitation.lastName {
                descriptionStart += "\(lastName)"
            }
        }
         
        if let sourceDate = newsCitation.sourceDateString {
            descriptionStart += "(\(sourceDate)). "
        } else {
            descriptionStart += ". "
        }
        
        let descriptionStartAttributedString = NSAttributedString(string: descriptionStart, attributes: attributes)
        
        var publicationText = ""
        if let publication = newsCitation.publication {
            publicationText = "\(publication). "
        }
        
        let publicationAttributedString = NSAttributedString(string: publicationText, attributes: italicAttributes)
        
        var retrievedString = ""
        if let accessDate = newsCitation.accessDateString {
            retrievedString = String.localizedStringWithFormat(CommonStrings.newNewsReferenceRetrievedDate, accessDate)
        }
        
        let retrievedDateAttributedString = NSAttributedString(string: retrievedString, attributes: attributes)
        
        let finalMutableAttributedString = NSMutableAttributedString(string: "")
        finalMutableAttributedString.append(descriptionStartAttributedString)
        finalMutableAttributedString.append(titleAttributedString)
        finalMutableAttributedString.append(publicationAttributedString)
        finalMutableAttributedString.append(retrievedDateAttributedString)
        
        return finalMutableAttributedString.copy() as? NSAttributedString ?? NSAttributedString(string: "")
        
    }
    
    private func descriptionForBookCitation(_ bookCitation: SignificantEvents.Citation.Book, traitCollection: UITraitCollection, theme: Theme) -> NSAttributedString {
        
        let font = UIFont.wmf_font(.subheadline, compatibleWithTraitCollection: traitCollection)
        let italicFont = UIFont.wmf_font(.italicSubheadline, compatibleWithTraitCollection: traitCollection)
        let attributes = [NSAttributedString.Key.font: font,
                          NSAttributedString.Key.foregroundColor:
                            theme.colors.primaryText]
        let italicAttributes = [NSAttributedString.Key.font: italicFont,
                          NSAttributedString.Key.foregroundColor:
                            theme.colors.primaryText]
        
        let titleAttributedString = NSAttributedString(string: bookCitation.title, attributes: italicAttributes)
        
        var descriptionStart = ""
        if let firstName = bookCitation.firstName {
            if let lastName = bookCitation.lastName {
                descriptionStart += "\(lastName), \(firstName)"
            }
        } else {
            if let lastName = bookCitation.lastName {
                descriptionStart += "\(lastName)"
            }
        }
         
        if let yearOfPub = bookCitation.yearPublished {
            descriptionStart += "(\(yearOfPub)). "
        } else {
            descriptionStart += ". "
        }
        
        let descriptionStartAttributedString = NSAttributedString(string: descriptionStart, attributes: attributes)
        
        var descriptionMiddle = ""
        if let locationPublished = bookCitation.locationPublished {
            if let publisher = bookCitation.publisher {
                descriptionMiddle += "\(locationPublished): \(publisher). "
            } else {
                descriptionMiddle += "\(locationPublished). "
            }
        } else {
            if let publisher = bookCitation.publisher {
                descriptionMiddle += "\(publisher). "
            }
        }
        
        if let pagesCited = bookCitation.pagesCited {
            descriptionMiddle += "pp. \(pagesCited)"
        }
        
        let descriptionMiddleAttributedString = NSAttributedString(string: descriptionMiddle, attributes: attributes)
        
        let isbnAttributedString: NSAttributedString
        if let isbn = bookCitation.isbn {
            let mutableAttributedString = NSMutableAttributedString(string: isbn, attributes: attributes)
            let isbnTitle = "Special:BookSources"
            let isbnURL = Configuration.current.articleURLForHost(Configuration.Domain.englishWikipedia, appending: [isbnTitle, isbn]).url
            let range = NSRange(location: 0, length: isbn.count)
            if let isbnURL = isbnURL {
                mutableAttributedString.addAttributes([NSAttributedString.Key.link : isbnURL,
                                             NSAttributedString.Key.foregroundColor: theme.colors.link], range: range)
            } else {
                mutableAttributedString.addAttributes(attributes, range: range)
            }
            
            isbnAttributedString = mutableAttributedString.copy() as? NSAttributedString ?? NSAttributedString(string: "")
        } else {
            isbnAttributedString = NSAttributedString(string: "")
        }
        
        let finalMutableAttributedString = NSMutableAttributedString(string: "")
        finalMutableAttributedString.append(descriptionStartAttributedString)
        finalMutableAttributedString.append(titleAttributedString)
        finalMutableAttributedString.append(descriptionMiddleAttributedString)
        finalMutableAttributedString.append(isbnAttributedString)
        
        return finalMutableAttributedString.copy() as? NSAttributedString ?? NSAttributedString(string: "")
        
    }
    
    private func getTimestampString() -> String? {
        switch typedEvent {
        case .newTalkPageTopic(let newTalkPageTopic):
            return newTalkPageTopic.timestampString
        case .large(let largeChange):
            return largeChange.timestampString
        case .vandalismRevert(let vandalismRevert):
            return vandalismRevert.timestampString
        case .small:
            return nil
        }
    }
    
    //Only used in the html portion of the feature
    func fullyRelativeTimestampForDisplay() -> String? {
        
        guard let timestampString = getTimestampString() else {
            return nil
        }
        
        return ArticleAsLivingDocViewModel.displayTimestamp(timestampString: timestampString, fullyRelative: true)
    }
    
    func timestampForDisplay() -> String? {
        if let displayTimestamp = displayTimestamp {
            return displayTimestamp
        }
        
        if let timestampString = getTimestampString() {
            let displayTimestamp = ArticleAsLivingDocViewModel.displayTimestamp(timestampString: timestampString, fullyRelative: false)
            self.displayTimestamp = displayTimestamp
        }
        
        return displayTimestamp
    }
    
    private func userNameAndEditCount() -> (userName: String, editCount: UInt?)? {
        let userName: String
        let editCount: UInt?
        switch typedEvent {
        case .newTalkPageTopic(let newTalkPageTopic):
            userName = newTalkPageTopic.user
            editCount = newTalkPageTopic.userEditCount
        case .large(let largeChange):
            userName = largeChange.user
            editCount = largeChange.userEditCount
        case .vandalismRevert(let vandalismRevert):
            userName = vandalismRevert.user
            editCount = vandalismRevert.userEditCount
        case .small:
            return nil
        }
        
        return (userName: userName, editCount: editCount)
    }
    
    static var botIconName: String {
        return "article-as-living-doc-bot"
    }
    
    private func userInfoHtmlSnippet() -> String? {
        guard let userNameAndEditCount = self.userNameAndEditCount() else {
            assertionFailure("Shouldn't reach this point")
            return nil
        }
        let userName = userNameAndEditCount.userName
        let editCount = userNameAndEditCount.editCount
        
        if let editCount = editCount,
           userType != .anonymous {
            let formattedEditCount = ArticleAsLivingDocViewModel.Event.Large.editCountFormatter.string(from: NSNumber(value: editCount)) ?? String(editCount)
            let userInfo = String.localizedStringWithFormat( CommonStrings.revisionUserInfo, userName, formattedEditCount)
            
            let rangeOfUserName = (userInfo as NSString).range(of: userName)
            let rangeValid = rangeOfUserName.location != NSNotFound && rangeOfUserName.location + rangeOfUserName.length <= userInfo.count
            let userNameHrefString = "./User:\(userName)"
            if rangeValid {
                
                let mutableUserInfo = NSMutableString(string: userInfo)
                
                let linkStartInsert: String
                if userType == .bot {
                    linkStartInsert = "<a href='\(userNameHrefString)'><img src='\(Self.botIconName)' style='margin: 0em .2em .35em .1em; width: 1em' />"
                } else {
                    linkStartInsert = "<a href='\(userNameHrefString)'>"
                }
                let linkEndInsert = "</a>"
                mutableUserInfo.insert(linkStartInsert, at: rangeOfUserName.location)
                mutableUserInfo.insert(linkEndInsert, at: rangeOfUserName.location + rangeOfUserName.length + linkStartInsert.count)
                
                if let userInfoResult = mutableUserInfo.copy() as? NSString {
                    return (userInfoResult as String)
                } else {
                    assertionFailure("This shouldn't happen")
                    return nil
                }
            }
        } else {
            let anonymousUserInfo = String.localizedStringWithFormat(CommonStrings.revisionUserInfoAnonymous, userName)
            return anonymousUserInfo
        }
        
        return nil
    }
    
    func userInfoForTraitCollection(_ traitCollection: UITraitCollection, theme: Theme) -> NSAttributedString {
        if let lastTraitCollection = lastTraitCollection,
           let userInfo = userInfo {
            if lastTraitCollection == traitCollection {
                return userInfo
            }
        }
        
        guard let userNameAndEditCount = self.userNameAndEditCount() else {
            assertionFailure("Shouldn't reach this point")
            return NSAttributedString(string: "")
        }
        let userName = userNameAndEditCount.userName
        let editCount = userNameAndEditCount.editCount
        
        var attributedString: NSAttributedString
        if let editCount = editCount,
           userType != .anonymous {
            let formattedEditCount = ArticleAsLivingDocViewModel.Event.Large.editCountFormatter.string(from: NSNumber(value: editCount)) ?? String(editCount)
            let userInfo = String.localizedStringWithFormat( CommonStrings.revisionUserInfo, userName, formattedEditCount)
            
            let font = UIFont.wmf_font(.subheadline, compatibleWithTraitCollection: traitCollection)
            let attributes = [NSAttributedString.Key.font: font,
                              NSAttributedString.Key.foregroundColor: theme.colors.secondaryText]
            let rangeOfUserName = (userInfo as NSString).range(of: userName)
            let rangeValid = rangeOfUserName.location != NSNotFound && rangeOfUserName.location + rangeOfUserName.length <= userInfo.count
            if let title = "User:\(userName)".percentEncodedPageTitleForPathComponents {
                let userNameURL = Configuration.current.articleURLForHost(Configuration.Domain.englishWikipedia, appending: [title]).url
                if let userNameURL = userNameURL,
                   rangeValid {
                    let mutableAttributedString = NSMutableAttributedString(string: userInfo, attributes: attributes)
                    mutableAttributedString.addAttribute(NSAttributedString.Key.link, value: userNameURL as NSURL, range: rangeOfUserName)
                    mutableAttributedString.addAttribute(NSAttributedString.Key.foregroundColor, value: theme.colors.link, range: rangeOfUserName)
                    
                    if let attributedString = mutableAttributedString.copy() as? NSAttributedString {
                        return attributedString
                    } else {
                        assertionFailure("This shouldn't happen")
                    }
                }
            }
            
            attributedString = NSAttributedString(string: userInfo, attributes: attributes)
        } else {
            let anonymousUserInfo = String.localizedStringWithFormat(CommonStrings.revisionUserInfoAnonymous, userName)
            
            let font = UIFont.wmf_font(.subheadline, compatibleWithTraitCollection: traitCollection)
            let attributes = [NSAttributedString.Key.font: font,
                              NSAttributedString.Key.foregroundColor: theme.colors.secondaryText]
            attributedString = NSAttributedString(string: anonymousUserInfo, attributes: attributes)
        }
        
        self.userInfo = attributedString
        self.lastTraitCollection = traitCollection
        return attributedString
    }
    
}
