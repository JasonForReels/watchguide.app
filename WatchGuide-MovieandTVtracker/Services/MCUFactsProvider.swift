import Foundation

struct MCUFactsProvider {
    static func getMCUFranchise() -> Franchise {
        let sessions = [
            // Phase 1 - Iron Man
            TriviaSession(
                mediaItem: mockMediaItem(id: 1726, title: "Iron Man", poster: "/781tYvS9Anp7Y7v7iObe85S5mhr.jpg"),
                videoKey: "8hYlB38asqk",
                facts: [
                    TriviaFact(text: "Did you know? Robert Downey Jr. used to hide food all over the lab set so he could snack during scenes. Most of his snacking on screen was unscripted!", startTime: 8)
                ],
                releaseDate: date(y: 2008, m: 5, d: 2),
                chronologicalDate: date(y: 2010, m: 5, d: 2) // IM1, IM2, and Thor happen in the same week "Fury's Big Week"
            ),
            
            // Captain America: The First Avenger (Chronologically First)
            TriviaSession(
                mediaItem: mockMediaItem(id: 1771, title: "Captain America: The First Avenger", poster: "/vSN1Y6LsM8M4pZFIXqlQU5IuJy.jpg"),
                videoKey: "JerVrbLldXw",
                facts: [
                    TriviaFact(text: "Chris Evans declined the role of Steve Rogers three times before finally accepting. He was wary of the fame and long-term commitment.", startTime: 12)
                ],
                releaseDate: date(y: 2011, m: 7, d: 22),
                chronologicalDate: date(y: 1942, m: 3, d: 1)
            ),
            
            // Thor
            TriviaSession(
                mediaItem: mockMediaItem(id: 10195, title: "Thor", poster: "/prbmO97vQR7qWDbZxN9879q7v.jpg"),
                videoKey: "JOddp-nlNvQ",
                facts: [
                    TriviaFact(text: "Tom Hiddleston originally auditioned for the role of Thor. He even bulked up for the part, but the producers saw him as the perfect Loki instead.", startTime: 15)
                ],
                releaseDate: date(y: 2011, m: 5, d: 6)
            ),
            
            // The Avengers
            TriviaSession(
                mediaItem: mockMediaItem(id: 24428, title: "The Avengers", poster: "/RY72SwwBvCU1sLp63UvOTvSNa5.jpg"),
                videoKey: "eOrNdBzoRuE",
                facts: [
                    TriviaFact(text: "The famous 'Shawarma' post-credits scene was filmed a day after the movie's premiere! Chris Evans had to hide a beard he was growing for another movie.", startTime: 20)
                ],
                releaseDate: date(y: 2012, m: 5, d: 4)
            ),
            
            // Guardians of the Galaxy
            TriviaSession(
                mediaItem: mockMediaItem(id: 118340, title: "Guardians of the Galaxy", poster: "/r7DuyYJszv1qqvMvBj7sy3uGv.jpg"),
                videoKey: "d96cjJhvlMA",
                facts: [
                    TriviaFact(text: "Chris Pratt reportedly stole his Star-Lord costume from the set just so he could wear it while visiting children in hospitals.", startTime: 10)
                ],
                releaseDate: date(y: 2014, m: 8, d: 1)
            ),
            
            // Black Panther
            TriviaSession(
                mediaItem: mockMediaItem(id: 284054, title: "Black Panther", poster: "/uxzzu9j77NofSNoI3v6E56I8Csl.jpg"),
                videoKey: "xjDjI45CniU",
                facts: [
                    TriviaFact(text: "To prepare for his role as Killmonger, Michael B. Jordan kept himself isolated from the rest of the cast during filming.", startTime: 15)
                ],
                releaseDate: date(y: 2018, m: 2, d: 16)
            ),
            
            // Avengers: Endgame
            TriviaSession(
                mediaItem: mockMediaItem(id: 299534, title: "Avengers: Endgame", poster: "/or06vS3nBvW6zB9pX9PTCOj97pL.jpg"),
                videoKey: "TcMBFSGVi1c",
                facts: [
                    TriviaFact(text: "Robert Downey Jr. was the only actor who was allowed to read the full script for Endgame to maintain total secrecy for the film's climax.", startTime: 30)
                ],
                releaseDate: date(y: 2019, m: 4, d: 26)
            ),
            
            // Spider-Man: No Way Home
            TriviaSession(
                mediaItem: mockMediaItem(id: 634649, title: "Spider-Man: No Way Home", poster: "/1g0dhvR8n917p6vqi59pznMvO.jpg"),
                videoKey: "JfVOs4VSpmA",
                facts: [
                    TriviaFact(text: "Andrew Garfield and Tobey Maguire were snuck onto the set under cloaks to prevent their involvement from leaking to the public.", startTime: 25)
                ],
                releaseDate: date(y: 2021, m: 12, d: 17)
            ),
            
            // Meta Fact 1: The Acquisition
            TriviaSession(
                mediaItem: MediaItem(id: -1, title: "Marvel Studios", name: nil, originalTitle: nil, originalName: nil, overview: "General Trivia", posterPath: nil, backdropPath: nil, releaseDate: nil, firstAirDate: nil, voteAverage: nil, voteCount: nil, popularity: nil, genreIds: nil, mediaType: "movie", adult: nil, originalLanguage: nil),
                videoKey: "qfB6k7p__tQ", // Generic Marvel intro/fanfare
                facts: [
                    TriviaFact(text: "Did you know? Disney bought Marvel Entertainment on December 31, 2009, for just $4.24 billion. It is widely considered one of the smartest acquisitions in history.", startTime: 5, isMetaFact: true)
                ],
                releaseDate: date(y: 2009, m: 12, d: 31),
                chronologicalDate: date(y: 2009, m: 12, d: 31)
            ),
            
            // Meta Fact 2: The Revenue
            TriviaSession(
                mediaItem: MediaItem(id: -2, title: "The MCU Legacy", name: nil, originalTitle: nil, originalName: nil, overview: "Financial stats", posterPath: nil, backdropPath: nil, releaseDate: nil, firstAirDate: nil, voteAverage: nil, voteCount: nil, popularity: nil, genreIds: nil, mediaType: "movie", adult: nil, originalLanguage: nil),
                videoKey: "8_vO_00Z9uY", // Marvel 10 years celebration or similar
                facts: [
                    TriviaFact(text: "Since its launch in 2008, the Marvel Cinematic Universe has grossed over $31 billion worldwide, making it the highest-grossing film franchise of all time.", startTime: 5, isMetaFact: true)
                ],
                releaseDate: date(y: 2026, m: 4, d: 16),
                chronologicalDate: date(y: 2026, m: 4, d: 16)
            )
        ]
        
        return Franchise(
            id: "mcu",
            name: "Marvel Cinematic Universe",
            description: "Explore the facts behind the world's most successful cinematic timeline.",
            accentColor: "#E23636", // Marvel Red
            iconName: "shield.fill",
            sessions: sessions
        )
    }
    
    // MARK: - Helpers
    private static func date(y: Int, m: Int, d: Int) -> Date {
        var components = DateComponents()
        components.year = y
        components.month = m
        components.day = d
        return Calendar.current.date(from: components) ?? Date()
    }
    
    private static func mockMediaItem(id: Int, title: String, poster: String) -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            name: nil,
            originalTitle: title,
            originalName: nil,
            overview: "",
            posterPath: poster,
            backdropPath: nil,
            releaseDate: nil,
            firstAirDate: nil,
            voteAverage: 8.0,
            voteCount: 1000,
            popularity: 100.0,
            genreIds: [],
            mediaType: "movie",
            adult: false,
            originalLanguage: "en"
        )
    }
}
