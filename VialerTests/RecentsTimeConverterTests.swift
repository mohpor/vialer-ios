//
//  RecentsTimeConverterTests.swift
//  Copyright © 2016 VoIPGRID. All rights reserved.
//

import XCTest

class RecentsTimeConverterTests: XCTestCase {

    var recentsTimeConverter = RecentsTimeConverter()
    var calendar = NSCalendar.currentCalendar()

    var usersLocalShortStyleDateFormatter: NSDateFormatter {
        let formatter = NSDateFormatter()
        formatter.timeZone = NSTimeZone.localTimeZone()
        formatter.dateStyle = NSDateFormatterStyle.ShortStyle
        return formatter
    }

    var usersLocalShortStyleTimeFormatter: NSDateFormatter {
        let formatter = NSDateFormatter()
        formatter.timeZone = NSTimeZone.localTimeZone()
        formatter.timeStyle = NSDateFormatterStyle.ShortStyle
        return formatter
    }


    /**
     Test creates an "API expected time string" from the given components and
     verifies that a correct NSDate object representing this time string is created.
     */
    func test24hCETstringGivesCorrectDate() {
        // Given
        let components = NSDateComponents()
        components.year = 2009
        components.month = 10
        components.day = 11
        components.hour = 12
        components.minute = 13
        components.second = 14

        // Constructs a 24h CET time string as expected by the API in the format
        // yyyy-MM-dd'T'HH:mm:ss (this seems to be ISO-8601)
        let string24hCET = "\(components.year)-\(components.month)-\(components.day)T\(components.hour):\(components.minute):\(components.second)"

        // When
        let receivedDate = recentsTimeConverter.dateFrom24hCET(timeString: string24hCET)

        // Then
        let expectedDate = calendar.dateFromComponents(components)!
        XCTAssert(receivedDate == expectedDate)
    }

    /**
     Test creates an NSDate object from the given components and verifies that a
     correct "API expected time string" is returned.
     */
    func testClassGivesAPI24hCETStringFromGivenDate() {
        // Given
        let components = NSDateComponents()
        components.year = 2009
        components.month = 10
        components.day = 11
        components.hour = 12
        components.minute = 13
        components.second = 14
        let dateToConvert = calendar.dateFromComponents(components)

        // When
        let receivedAPIformatted24hCETstring = recentsTimeConverter.apiFormatted24hCETstringFrom(date: dateToConvert!)

        // Then
        let expected24hAPIstring = "\(components.year)-\(components.month)-\(components.day)T\(components.hour):\(components.minute):\(components.second)"
        XCTAssert(receivedAPIformatted24hCETstring == expected24hAPIstring)
    }

    /**
     Passing a time one second AFTER midnight e.g. this day, the test verifies
     that the relative Day/Time string returned is a time (hh:mm)
     */
    func testRelativeDayTimeStringGivesTime() {
        // Given
        let components = dayMonthYearComponentsFromNow()

        components.second = 1
        let oneSecondAfterMidnightToday = calendar.dateFromComponents(components)

        // When
        let receivedRelativeDateString = recentsTimeConverter.relativeDayTimeStringFrom(date: oneSecondAfterMidnightToday!)

        // Then
        let expectedShortTimeString = usersLocalShortStyleTimeFormatter.stringFromDate(oneSecondAfterMidnightToday!)
        XCTAssert(receivedRelativeDateString == expectedShortTimeString)
    }

    /**
     Passing a time one second BEFORE midnight e.g. yesterday, the test verifies
     that the relative Day/Time string returned is "yesterday"
     */
    func testRelativeDayTimeStringGivesYesterday() {
        // Given
        let components = dayMonthYearComponentsFromNow()

        components.second = -1
        let oneSecondBeforeMidnightYesterday = calendar.dateFromComponents(components)

        // When
        let expectedRelativeDateString = NSLocalizedString("yesterday", comment: "")

        // Then
        XCTAssert(recentsTimeConverter.relativeDayTimeStringFrom(date: oneSecondBeforeMidnightYesterday!) == expectedRelativeDateString)
    }

    /**
     Passing a time one second BEFORE midnight yesterday, so a time before yesterday 
     the test verifies that the relative Day/Time string returned is a date (dd:MM)
     */
    func testRelativeDayTimeStringGivesDateInPast() {
        // Given
        let components = dayMonthYearComponentsFromNow()

        components.second = -1
        components.day = components.day-1

        // When
        let oneSecondBeforeMidnightOnTheDayBeforeYesterday = calendar.dateFromComponents(components)

        // Then
        let expectedShortDateString = usersLocalShortStyleDateFormatter.stringFromDate(oneSecondBeforeMidnightOnTheDayBeforeYesterday!)
         XCTAssert(recentsTimeConverter.relativeDayTimeStringFrom(date: oneSecondBeforeMidnightOnTheDayBeforeYesterday!) == expectedShortDateString)
    }

    // MARK: Helper functions
    func dayMonthYearComponentsFromNow() -> NSDateComponents {
        let date = NSDate()
        let unitFlags: NSCalendarUnit = [.Day, .Month, .Year]
        return calendar.components(unitFlags, fromDate: date)
    }
}
