import SwiftUI

extension Font {
    // MARK: - Hero & Large Titles
    /// Massive light-weight headline used for stats and large empty states (56pt)
    public static var j7Hero: Font {
        .system(size: 56, weight: .light, design: .default)
    }
    
    /// Large light-weight screen headers (28pt)
    public static var j7TitleLarge: Font {
        .system(size: 28, weight: .light, design: .default)
    }

    // MARK: - Titles (1, 2, 3)
    /// Primary book and chapter titles (26pt bold serif)
    public static var j7Title1Serif: Font {
        .system(size: 26, weight: .bold, design: .serif)
    }
    
    /// Primary UI section titles (24pt bold sans)
    public static var j7Title1: Font {
        .system(size: 24, weight: .bold, design: .default)
    }
    
    /// Secondary screen or modal header (22pt semibold sans)
    public static var j7Title2: Font {
        .system(size: 22, weight: .semibold, design: .default)
    }
    
    /// Tertiary UI titles / bold options (18pt semibold sans)
    public static var j7Title3: Font {
        .system(size: 18, weight: .semibold, design: .default)
    }
    
    /// Tertiary serif book titles / subtitles (20pt semibold serif)
    public static var j7Title3Serif: Font {
        .system(size: 20, weight: .semibold, design: .serif)
    }

    // MARK: - Body & Content
    /// Standard UI body text (15pt regular sans)
    public static var j7Body: Font {
        .system(size: 15, weight: .regular, design: .default)
    }
    
    /// Semi-bold UI body text (15pt semibold sans)
    public static var j7BodyMedium: Font {
        .system(size: 15, weight: .semibold, design: .default)
    }
    
    /// Bold UI body text (15pt bold sans)
    public static var j7BodyBold: Font {
        .system(size: 15, weight: .bold, design: .default)
    }
    
    /// Standard reading text helper for default 18pt size (18pt regular serif)
    public static var j7BodySerif: Font {
        .system(size: 18, weight: .regular, design: .serif)
    }
    
    /// Standard reading text helper for highlighted states (18pt medium serif)
    public static var j7BodySerifMedium: Font {
        .system(size: 18, weight: .medium, design: .serif)
    }
    
    /// Bold reading text helper / book titles in grids (18pt bold serif)
    public static var j7BodySerifBold: Font {
        .system(size: 18, weight: .bold, design: .serif)
    }

    /// Unified parametrized builder for user-customizable reader font sizes
    public static func j7BookContent(size: Double, weight: Font.Weight = .regular) -> Font {
        .system(size: CGFloat(size), weight: weight, design: .serif)
    }

    // MARK: - Subheadlines
    /// Standard metadata labels and helper texts (13pt medium sans)
    public static var j7Subheadline: Font {
        .system(size: 13, weight: .medium, design: .default)
    }
    
    /// Semi-bold metadata labels (13pt semibold sans)
    public static var j7SubheadlineSemibold: Font {
        .system(size: 13, weight: .semibold, design: .default)
    }
    
    /// Bold subheadings (13pt bold sans)
    public static var j7SubheadlineBold: Font {
        .system(size: 13, weight: .bold, design: .default)
    }
    
    /// Bold serif subheadings (13pt bold serif)
    public static var j7SubheadlineSerifBold: Font {
        .system(size: 13, weight: .bold, design: .serif)
    }

    // MARK: - Captions & Metadata
    /// Standard small details and minor text (11pt regular sans)
    public static var j7Caption: Font {
        .system(size: 11, weight: .regular, design: .default)
    }
    
    /// Semi-bold small detail labels (11pt semibold sans)
    public static var j7CaptionMedium: Font {
        .system(size: 11, weight: .semibold, design: .default)
    }
    
    /// Bold small detail labels (11pt bold sans)
    public static var j7CaptionBold: Font {
        .system(size: 11, weight: .bold, design: .default)
    }
    
    /// Bold serif small detail labels (11pt bold serif)
    public static var j7CaptionSerifBold: Font {
        .system(size: 11, weight: .bold, design: .serif)
    }
    
    /// Ultra-small labels/badges (9pt regular sans)
    public static var j7Caption2: Font {
        .system(size: 9, weight: .regular, design: .default)
    }
    
    /// Ultra-small bold labels/badges (9pt bold sans)
    public static var j7Caption2Bold: Font {
        .system(size: 9, weight: .bold, design: .default)
    }
}
