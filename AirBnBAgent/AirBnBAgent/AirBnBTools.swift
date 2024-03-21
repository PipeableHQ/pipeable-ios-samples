import Foundation
import OpenAI
import PipeableSDK

enum AirBnbToolError: Error {
    case assertionFailure(reason: String)
}

class AirBnBTools {
    /*
     This is the main class that interacts with the AirBnB website.
     * We use PipeableSDK to interact with the website.
     * We expose a list of tools (see `tools` below) that the Agent can provide to OpenAI.
     * We also expose a function `maybeCallTool` that the Agent can call when GPT calls a tool, this handles
       parsing the arguments for the tool call and storing them in the appropriate properties.
     * We also expose a function `stepCompleted` that the Agent can call when all tools in an OpenAI response have been
       called, this function takes any action that might require the results of multiple tool calls.
     * We expose a `login` function that the WebView can call to log the user in to AirBnB.
     */
    private var page: PipeablePage

    // The following properties are used to store the user's requirements as they are extracted from the user's request
    // using GPT function calls. Once all the requirements are extracted, the search is carried out.
    private var destination: SelectDestinationParams?
    private var dates: SelectDatesParams?
    private var guests: SelectGuestsParams?
    // This ensures that the search is only carried out once.
    private var calledSearch = false

    // Used to store the user's requirements once they are extracted using GPT function calls.
    private var filters: AirBnBFilters?
    // This ensures that the filters are only applied once.
    private var calledFilter = false

    private var shouldBookAirBnb = false
    private var selectedAirBnB = false

    init(page: PipeablePage) {
        self.page = page
    }

    // Waits for the user to log in.
    func login() async throws {
        _ = try await page.goto("https://www.airbnb.com/login", waitUntil: .networkidle)
        // Wait for the user to be redirected back to the home page, we assume this means the
        // user logged in successfully. Allow for more time for them to login.
        _ = try await page.waitForURL(
            { url in url == "https://www.airbnb.com/" },
            timeout: 180_000,
            ignoreNavigationErrors: true // So that we ignore errors caused by Login with Apple.
        )
    }

    // Function for GPT to call to record the user's destination choice
    private let selectDestinationFn = ChatQuery.ChatCompletionToolParam(function: .init(
        name: "selectDestination",
        description: "Select a destination from the dropdown",
        parameters: .init(
            type: .object,
            properties: [
                "destination": .init(type: .string, description: "the destination to select"),
            ],
            required: ["destination"]
        )
    ))

    // Used to decode GPT's JSON for function call
    private struct SelectDestinationParams: Codable {
        let destination: String
    }

    // Function for GPT to call to record the user's travel dates
    private let selectDatesFn = ChatQuery.ChatCompletionToolParam(function: .init(
        name: "selectDates",
        description: "Select the check-in and check-out dates",
        parameters: .init(
            type: .object,
            properties: [
                "checkIn": .init(type: .string, description: "The check-in date, formatted as MM/DD/YYYY"),
                "checkOut": .init(type: .string, description: "The check-out date, formatted as MM/DD/YYYY"),
            ],
            required: ["checkIn", "checkOut"]
        )
    ))

    // Used to decode GPT's JSON for function call
    private struct SelectDatesParams: Codable {
        let checkIn: String
        let checkOut: String
    }

    // Function for GPT to call to record the user's requested number of guests
    private let selectGuestsFn = ChatQuery.ChatCompletionToolParam(function: .init(
        name: "selectGuests",
        description: "Select the number of guests",
        parameters: .init(
            type: .object,
            properties: [
                "adults": .init(type: .integer, description: "The number of adults"),
                "children": .init(type: .integer, description: "The number of children"),
                "infants": .init(type: .integer, description: "The number of infants"),
                "pets": .init(type: .integer, description: "The number of infants"),
            ],
            required: ["adults", "children", "infants", "pets"]
        )
    ))

    // Used to decode GPT's JSON for function call
    private struct SelectGuestsParams: Codable {
        let adults: Int
        let children: Int
        let infants: Int
        let pets: Int
    }

    // Function for GPT to book the top airbnb
    private let bookTopAirBnBFn = ChatQuery.ChatCompletionToolParam(function: .init(
        name: "bookTopAirBnB",
        description: "Select the top, highest ranked AirBnB and go to the booking page"
    ))

    // Uses PipeableSDK to carry out a search on behalf of the user once GPT has recorded the user's
    // travel requirements as GPT function calls.
    private func searchDestinations(
        place: String,
        startDate: String,
        endDate: String,
        guests: SelectGuestsParams
    ) async throws {
        let searchInput = try await page.waitForSelector("button[aria-describedby='searchInputDescriptionId']", visible: true)
        try await searchInput?.click()

        // Search destinations input
        let searchButtonInput = try? await page.waitForXPath("//button[contains(string(), 'Search destinations')]")
        try await searchButtonInput?.click()

        let destionationInputEl = try? await page.waitForSelector("input[data-testid='search_query_input']", visible: true)
        try await Task.sleep(nanoseconds: 500 * 1_000_000)
        try await destionationInputEl?.click()

        //
        try await destionationInputEl?.type(place, delay: 100)

        try await Task.sleep(nanoseconds: 200 * 1_000_000)

        let resultEntry = try await page.waitForXPath("//div[contains(@data-testid, 'option-') and contains(string(), '" + place + "')]")
        try await resultEntry?.click()

        try await Task.sleep(nanoseconds: 1 * 1_000_000_000)

        _ = try await page.waitForXPath("//div[@id='accordion-body-/homes-when']", visible: true)

        // Select start date.
        let startDateEl = try await page.waitForSelector("div[data-testid='calendar-day-" + startDate + "']")
        try await startDateEl?.click()

        try await Task.sleep(nanoseconds: 1 * 1_000_000_000)

        // Select end date.
        let endDateEl = try await page.waitForSelector("div[data-testid='calendar-day-" + endDate + "']")
        try await endDateEl?.click()

        try await Task.sleep(nanoseconds: 1 * 1_000_000_000)

        // Click next
        guard let nextButton = try await page.waitForSelector("div[data-testid='dates-footer-primary-btn']") else {
            throw AirBnbToolError.assertionFailure(reason: "Next button on dates not found")
        }

        try await nextButton.click()

        _ = try await page.waitForXPath("//div[@id='accordion-body-/homes-who']", visible: true)

        func increaseGuests(_ gt: String, _ num: Int) async throws {
            guard let stepper = try await page.waitForSelector("button[data-testid='stepper-\(gt)-increase-button']") else {
                throw AirBnbToolError.assertionFailure(reason: "Could not find increase button for \(gt)")
            }
            for _ in 0 ..< num {
                try await stepper.click()
                try await Task.sleep(nanoseconds: 500 * 1_000_000)
            }

            // validate counter
            let countEl = try await page.waitForSelector("span[data-testid='stepper-\(gt)-value']")
            let countValue = try await countEl?.textContent()
            if countValue != String(num) {
                throw AirBnbToolError.assertionFailure(reason: "\(gt) guests do not match: \(countValue ?? "no value") vs \(String(num))")
            }
        }
        if guests.adults > 0 {
            try await increaseGuests("adults", guests.adults)
            try await Task.sleep(nanoseconds: 1 * 1_000_000_000)
        }
        if guests.children > 0 {
            try await increaseGuests("children", guests.children)
            try await Task.sleep(nanoseconds: 1 * 1_000_000_000)
        }
        if guests.infants > 0 {
            try await increaseGuests("infants", guests.infants)
            try await Task.sleep(nanoseconds: 1 * 1_000_000_000)
        }
        if guests.pets > 0 {
            try await increaseGuests("pets", guests.pets)
            try await Task.sleep(nanoseconds: 1 * 1_000_000_000)
        }

        let searchBtn = try await page.waitForSelector("*[data-testid='explore-footer-primary-btn']")
        try await searchBtn?.click()
        try await Task.sleep(nanoseconds: 1_000 * 1_000_000)
    }

    private let selectFiltersFn = ChatQuery.ChatCompletionToolParam(function: .init(
        name: "selectFilters",
        description: "Select filters to refine search results",
        parameters: .init(
            type: .object,
            properties: [
                "typeOfPlace": .init(type: .string, description: "The type of place to filter by", enum: ["Any type", "Room", "Entire home"]),
                "priceRangeMin": .init(type: .integer, description: "The minimum price per night to filter by", minimum: 0),
                "priceRangeMax": .init(type: .integer, description: "The maximum price per night to filter by", minimum: 0),
                "instantBook": .init(type: .boolean, description: "Whether to filter by instant book availability"),
            ],
            required: ["typeOfPlace", "priceRangeMin", "priceRangeMax", "instantBook"]
        )
    ))

    private struct AirBnBFilters: Codable {
        enum TypeOfPlace: String, Codable {
            case anyType = "Any type"
            case room = "Room"
            case entireHome = "Entire home"
        }

        var typeOfPlace: TypeOfPlace?
        var priceRangeMin: UInt?
        var priceRangeMax: UInt?

        var instantBook: Bool?
    }

    // Uses PipeableSDK to apply filters to the search results once GPT has recorded the user's
    // filter requirements as GPT function calls.
    private func applyFilters(filters: AirBnBFilters) async throws {
        let buttonFilter = try await page.waitForSelector("button[aria-label='Show filters']", visible: true)
        try? await buttonFilter?.click()

        _ = try await page.waitForXPath("//header[contains(string(), 'Filters')]", visible: true)

        if let typeOfPlace = filters.typeOfPlace {
            guard let btn = try await page.waitForSelector("button[aria-describedby='room-filter-description-" + typeOfPlace.rawValue + "']", visible: true) else {
                throw AirBnbToolError.assertionFailure(reason: "Could not type of place button")
            }

            _ = try await page.evaluateAsyncFunction("""
                el.scrollIntoView({ block: "center" });
            """, arguments: ["el": btn])

            try await Task.sleep(nanoseconds: 200 * 1_000_000)

            try await btn.click()
            try await Task.sleep(nanoseconds: 1_000 * 1_000_000)
        }

        if let priceRangeMin = filters.priceRangeMin {
            guard let priceInputMin = try await page.waitForSelector("input#price_filter_min", visible: true) else {
                throw AirBnbToolError.assertionFailure(reason: "Could not find price min")
            }

            _ = try await page.evaluateAsyncFunction("""
                el.scrollIntoView({ block: "center" });
            """, arguments: ["el": priceInputMin])
            try await Task.sleep(nanoseconds: 200 * 1_000_000)

            _ = try await page.evaluateAsyncFunction("""
                el.focus();
                el.select();
                document.execCommand('selectAll');
                document.execCommand('Delete')
            """, arguments: ["el": priceInputMin])

            try await Task.sleep(nanoseconds: 1_000 * 1_000_000)

            try await priceInputMin.type(String(priceRangeMin))
        }

        if let priceRangeMax = filters.priceRangeMax {
            guard let priceInputMax = try await page.waitForSelector("input#price_filter_max", visible: true) else {
                throw AirBnbToolError.assertionFailure(reason: "Could not find price max")
            }

            _ = try await page.evaluateAsyncFunction("""
                el.scrollIntoView({ block: "center" });
            """, arguments: ["el": priceInputMax])
            try await Task.sleep(nanoseconds: 200 * 1_000_000)

            _ = try await page.evaluateAsyncFunction("""
                el.focus();
                el.select();
                document.execCommand('selectAll');
                document.execCommand('Delete');
            """, arguments: ["el": priceInputMax])

            try await Task.sleep(nanoseconds: 300 * 1_000_000)

            try await priceInputMax.type(String(priceRangeMax))

            try await Task.sleep(nanoseconds: 1_000 * 1_000_000)
        }

        if let instantBook = filters.instantBook {
            if instantBook {
                guard let ibButton = try await page.waitForSelector("button#ib", visible: true) else {
                    throw AirBnbToolError.assertionFailure(reason: "Could not find button#ib")
                }

                _ = try await page.evaluateAsyncFunction("el.scrollIntoView(); window.scrollBy({ top: '-200'});", arguments: ["el": ibButton])

                try await Task.sleep(nanoseconds: 100 * 1_000_000)

                try await ibButton.click()

                // Wait to show it.
                try await Task.sleep(nanoseconds: 500 * 1_000_000)
            }
        }

        // always submit the search button, even if nothing changed, so the filters go away
        let searchBtn = try await page.waitForSelector("footer > a", visible: true)
        try await searchBtn?.click()

        _ = try await page.waitForResponse("/StaysSearch/")
    }

    private func selectTopAirBnB() async throws {
        guard let airbnbLink = try await page.waitForXPath("//div[@itemprop='itemListElement']/descendant::a", visible: true) else {
            return
        }

        _ = try await page.evaluateAsyncFunction("el.scrollIntoView()", arguments: ["el": airbnbLink])

        try await airbnbLink.click()

        _ = try await page.waitForResponse("stayCheckout")

        // Dismiss translation dialog if it appears, give it 3s to appear.
        do {
            let closeBtn = try await page.waitForSelector("div[aria-label='Translation on'] button[aria-label='Close']", timeout: 3_000)
            try? await closeBtn?.click()
            try await Task.sleep(nanoseconds: 300 * 1_000_000)
        } catch {
            // It's ok if it doesn't appear.
        }

        guard let bookButton = try await page.waitForSelector("button[data-testid='homes-pdp-cta-btn']", visible: true) else { return }

        _ = try await page.evaluateAsyncFunction("el.scrollIntoView()", arguments: ["el": bookButton])

        try await bookButton.click()
    }

    // The tools that we expose to the Agent for GPT to call
    var tools: [ChatQuery.ChatCompletionToolParam] {
        return [
            selectDestinationFn,
            selectDatesFn,
            selectGuestsFn,
            selectFiltersFn,
            bookTopAirBnBFn,
        ]
    }

    // Called by the Agent for each tool call that is returned by OpenAI, returns
    // true if the tool call was matched and handled.
    func maybeCallTool(name: String, jsonArgs: Data) throws -> Bool {
        var matched = true
        switch name {
        case "selectDestination":
            destination = try JSONDecoder().decode(SelectDestinationParams.self, from: jsonArgs)
        case "selectDates":
            dates = try JSONDecoder().decode(SelectDatesParams.self, from: jsonArgs)
        case "selectGuests":
            guests = try JSONDecoder().decode(SelectGuestsParams.self, from: jsonArgs)
        case "selectFilters":
            filters = try JSONDecoder().decode(AirBnBFilters.self, from: jsonArgs)
        case "bookTopAirBnB":
            shouldBookAirBnb = true
        default:
            matched = false
        }
        return matched
    }

    // Called by the Agent to signal that all tools have been called and we
    // should take any actions that might require the results of multiple tool calls.
    func stepCompleted(onStep: ((_ stepName: String) -> Void)?) async throws {
        if destination != nil, dates != nil, guests != nil, !calledSearch {
            if let onStep = onStep {
                onStep("Searching destination")
            }

            try await searchDestinations(place: destination!.destination, startDate: dates!.checkIn, endDate: dates!.checkOut, guests: guests!)

            calledSearch = true
        }

        if filters != nil, !calledFilter {
            if let onStep = onStep {
                onStep("Applying filters")
            }

            try await applyFilters(filters: filters!)
            calledFilter = true
        }

        if shouldBookAirBnb, !selectedAirBnB, calledSearch, calledFilter {
            if let onStep = onStep {
                onStep("Selecting AirBnB")
            }
            try await selectTopAirBnB()

            selectedAirBnB = true
        }
    }
}
