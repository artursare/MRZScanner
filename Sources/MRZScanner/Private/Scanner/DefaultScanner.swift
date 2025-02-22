//
//  DefaultScanner.swift
//  
//
//  Created by Roman Mazeev on 14.07.2021.
//

import CoreImage

struct DefaultScanner: Scanner {
    enum ScanningError: Error {
        case codeNotFound
    }

    enum ScanningType {
        case live
        case single
    }

    let textRecognizer: TextRecognizer
    let validator: Validator
    let parser: Parser

    init(textRecognizer: TextRecognizer, validator: Validator, parser: Parser) {
        self.textRecognizer = textRecognizer
        self.validator = validator
        self.parser = parser
    }

    func scan(
        scanningType: ScanningType,
        scanningImage: ScanningImage,
        orientation: CGImagePropertyOrientation,
        regionOfInterest: CGRect?,
        minimumTextHeight: Float?,
        recognitionLevel: RecognitionLevel,
        foundBoundingRectsHandler: (([CGRect]) -> Void)? = nil,
        completionHandler: @escaping (Result<DocumentScanningResult<ParsedResult>, Error>) -> Void
    ) {
        textRecognizer.recognize(
            scanningImage: scanningImage,
            orientation: orientation,
            regionOfInterest: regionOfInterest,
            minimumTextHeight: minimumTextHeight,
            recognitionLevel: .fast
        ) {
            switch $0 {
            case .success(let results):
                if scanningType == .live {
                    DispatchQueue.main.async {
                        foundBoundingRectsHandler?(results.map { $0.boundingRect })
                    }
                }

                let validatedResult = validator.getValidatedResults(from: results.map { $0.results })
                guard let parsedResult = parser.parse(lines: validatedResult.map { $0.result }) else {
                    if scanningType == .single {
                        DispatchQueue.main.async {
                            completionHandler(.failure(ScanningError.codeNotFound))
                        }
                    }
                    return
                }

                DispatchQueue.main.async {
                    completionHandler(.success(
                        .init(
                            result: parsedResult,
                            boundingRects: getScannedBoundingRects(
                                from: results,
                                validLines: validatedResult
                            )
                        )
                    ))
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completionHandler(.failure(error))
                }
            }
        }
    }

    private func getScannedBoundingRects(
        from results: [TextRecognizerResult],
        validLines: ValidatedResults
    ) -> ScannedBoundingRects {
        let allBoundingRects = results.map { $0.boundingRect }
        let validRectIndexes = validLines.map { $0.index }
        let validRects = allBoundingRects.enumerated()
            .filter { validRectIndexes.contains($0.offset) }
            .map { $0.element }
        let invalidRects = allBoundingRects.enumerated()
            .filter { !validRectIndexes.contains($0.offset) }
            .map { $0.element }

        return (validRects, invalidRects)
    }
}

