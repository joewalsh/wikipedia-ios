import Foundation

extension String {
    /// Converts HTML string to NSAttributedString by handling a limited subset of tags. Optionally bolds an additional string based on matching.
    ///
    /// This is used instead of alloc/init'ing the attributed string with @{NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType} because that approach proved to be slower and could't be called from a background thread. More info: https://developer.apple.com/documentation/foundation/nsattributedstring/1524613-initwithdata
    ///
    /// - Parameter textStyle: DynamicTextStyle to use with the resulting string
    /// - Parameter boldWeight: Font weight for bolded parts of the string
    /// - Parameter traitCollection: trait collection for font selection
    /// - Parameter color: Text color
    /// - Parameter handlingLinks: Whether or not link tags should be parsed and turned into links in the resulting string
    /// - Parameter linkColor: Link text color
    /// - Parameter handlingLists: Whether or not list tags should be parsed and styled in the resulting string
    /// - Parameter handlingSuperSubscripts: whether or not super and subscript tags should be parsed and styled in the resulting string
    /// - Parameter tagMapping: Lowercase string tag name to another lowercase string tag name - converts tags, for example, @{@"a":@"b"} will turn <a></a> tags to <b></b> tags
    /// - Parameter additionalTagAttributes: Additional text attributes for given tags - lowercase tag name to attribute key/value pairs
    /// - Returns: the resulting NSMutableAttributedString with styles applied to match the limited set of HTML tags that were parsed
    public func byAttributingHTML(with textStyle: DynamicTextStyle, boldWeight: UIFont.Weight = .semibold, matching traitCollection: UITraitCollection, color: UIColor? = nil, handlingLinks: Bool = true, linkColor: UIColor? = nil, handlingLists: Bool = false, handlingSuperSubscripts: Bool = false, tagMapping: [String: String]? = nil, additionalTagAttributes: [String: [NSAttributedString.Key: Any]]? = nil, boldingMatchesOf: String? = nil) -> NSMutableAttributedString {
        let font = UIFont.wmf_font(textStyle, compatibleWithTraitCollection: traitCollection)
        let boldFont = UIFont.wmf_font(textStyle.with(weight: boldWeight), compatibleWithTraitCollection: traitCollection)
        let italicFont = UIFont.wmf_font(textStyle.with(traits: [.traitItalic]), compatibleWithTraitCollection: traitCollection)
        let boldItalicFont = UIFont.wmf_font(textStyle.with(weight: boldWeight, traits: [.traitItalic]), compatibleWithTraitCollection: traitCollection)
        var stringToAttribute: String = self.wmf_stringByDecodingHTMLEntities()
        if let boldingMatchesOf {
            stringToAttribute.applyBoldTag(to: boldingMatchesOf)
        }
        return stringToAttribute.wmf_attributedStringFromHTML(
            with: font,
            boldFont: boldFont,
            italicFont: italicFont,
            boldItalicFont: boldItalicFont,
            color: color,
            linkColor: linkColor,
            handlingLinks: handlingLinks,
            handlingLists: handlingLists,
            handlingSuperSubscripts: handlingSuperSubscripts,
            decodingEntities: false,
            tagMapping: tagMapping,
            additionalTagAttributes: additionalTagAttributes
        )
    }
    
    public var removingHTML: String {
        return (self as NSString).wmf_stringByRemovingHTML()
    }
    
    private enum HTMLTag {
        static let boldStart = "<b>"
        static let boldEnd = "</b>"
    }
    
    /// Applies a bold tag to the first portion of the string that matches the given string.
    /// Should already have HTML entities (like &amp; &lt; etc.) decoded before calling this method.
    /// - Parameter matchingString: the string to search for and bold.
    public mutating func applyBoldTag(to matchingString: String) {
        guard let range = rangeOfFirstMatchInHTMLContent(of: matchingString) else {
            return
        }
        insert(contentsOf: HTMLTag.boldStart, at: range.lowerBound)
        insert(contentsOf: HTMLTag.boldEnd, at: index(range.upperBound, offsetBy: HTMLTag.boldStart.count))
    }
    
    public func rangeOfFirstMatchInHTMLContent(of matchingString: String) -> Range<Index>? {
        for contentRange in rangesOfHTMLContent {
            guard let matchingRange = range(of: matchingString, options: .caseInsensitive, range: contentRange) else {
                continue
            }
            return matchingRange
        }
        return nil
    }
    
    public var rangesOfHTMLContent: [Range<Index>] {
        let matches = NSRegularExpression.wmf_HTMLTag().matches(in: self, range: fullRange)
        var currentIndex = startIndex
        return matches.map(\.range).map { range in
            let matchStartIndex = index(startIndex, offsetBy: range.location)
            let matchEndIndex = index(matchStartIndex, offsetBy: range.length)
            let nonTagRange = currentIndex..<matchStartIndex
            currentIndex = matchEndIndex
            return nonTagRange
        } + [currentIndex..<endIndex]
    }
}
