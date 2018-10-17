//
//  SourceEditorCommand.swift
//  Data Formater Extension
//
//  Created by Sylvain Roux on 2018-10-17.
//  Copyright © 2018 Sylvain Roux. All rights reserved.
//

import Foundation
import XcodeKit

class SourceEditorCommand: NSObject, XCSourceEditorCommand {
    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void ) -> Void {
        if invocation.commandIdentifier == "\(Bundle.main.bundleIdentifier!).formatXML" {
            XMLFormater(with: invocation, completionHandler: completionHandler).format()
        }
        else if invocation.commandIdentifier == "\(Bundle.main.bundleIdentifier!).formatJSON" {
            JSONFormater(with: invocation, completionHandler: completionHandler).format()
        }
    }
}

class XMLFormater: NSObject, XMLParserDelegate {
    var invocation: XCSourceEditorCommandInvocation
    var completionHandler: ((Error?) -> Void)

    init(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void ) {
        self.invocation = invocation
        self.completionHandler = completionHandler
    }
    
    var formatedXml = ""
    var xmlDeclaration: String?
    var level: Int = 0
    var currentElementName: String?
    var foundCharacters: String = ""
    
    func format() {
        // Trim white spaces outside tags
        var allLines = NSString()
        for lineIndex in 0 ..< self.invocation.buffer.lines.count {
            let line = self.invocation.buffer.lines[lineIndex] as! NSString
            let trimmedLine = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            allLines = NSString(format: "%@%@", allLines, trimmedLine)
        }
        
        // Add XML declaration to the formated document
        let regex = try? NSRegularExpression(pattern: "<\\?xml.*\\?>", options: [])
        let string = allLines as String
        let matches = regex?.matches(in: string, options: [], range: NSRange(location: 0, length: string.count))
        if matches!.count != 0 {
            let range = matches![0].range(at: 0)
            let startIndex = string.index(string.startIndex, offsetBy: range.location)
            let index = string.index(startIndex, offsetBy: range.length)
            self.xmlDeclaration = String(string[..<index])
        }
        
        let data = allLines.data(using: String.Encoding.utf8.rawValue)!
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        let isXmlValid = xmlParser.parse()
        if !isXmlValid {
            self.invocation.buffer.lines.add("<!-- Error : Invalid XML document -->")
            self.completionHandler(nil)
        }
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        self.formatedXml += "\n"
        for _ in 0..<self.level {
            self.formatedXml += "    "
        }
        self.level += 1
        self.formatedXml += "<\(elementName)"
        for attribute in attributeDict {
            self.formatedXml += " \(attribute.key)=\"\(attribute.value)\""
        }
        self.formatedXml += ">"
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        self.foundCharacters += string
    }
    
    func parser(_ parser: XMLParser, foundComment comment: String) {
        self.formatedXml += "\n"
        for _ in 0..<self.level {
            self.formatedXml += "    "
        }
        self.formatedXml += "<!--\(comment)-->"
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        self.level -= 1
        if self.foundCharacters.count != 0 {
            self.formatedXml += self.foundCharacters
            self.foundCharacters = ""
        }
        else {
            self.formatedXml += "\n"
            for _ in 0..<self.level {
                self.formatedXml += "    "
            }
        }
        self.formatedXml += "</\(elementName)>"
    }
    
    func parserDidEndDocument(_ parser: XMLParser) {
        self.invocation.buffer.lines.removeAllObjects()
        var formatedXml = ""
        if self.xmlDeclaration != nil {
            formatedXml = self.xmlDeclaration! + self.formatedXml
        }
        else {
            formatedXml += self.formatedXml.dropFirst()
        }
        self.invocation.buffer.lines.add(formatedXml)
        self.completionHandler(nil)
    }
}

class JSONFormater: NSObject {
    var invocation: XCSourceEditorCommandInvocation
    var completionHandler: ((Error?) -> Void)
    
    init(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void ) {
        self.invocation = invocation
        self.completionHandler = completionHandler
    }
    
    var formatedJson = ""
    var level: Int = 0
    
    func format() {
        // Trim white spaces outside tags
        var allLines = NSString()
        for lineIndex in 0 ..< self.invocation.buffer.lines.count {
            let line = self.invocation.buffer.lines[lineIndex] as! NSString
            let trimmedLine = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            allLines = NSString(format: "%@%@", allLines, trimmedLine)
        }
        let string = String(allLines)
        
        if let anEncoding = string.data(using: String.Encoding.utf8) {
            guard let jsonObject = try? JSONSerialization.jsonObject(with: anEncoding, options: []) as! [String: Any] else {
                self.invocation.buffer.lines.add("{ \"Error\": \"Invalid JSON document\"}")
                self.completionHandler(nil)
                return
            }
            self.formatElement(jsonObject)
            self.formatedJson = "{\n\(self.formatedJson)\n}"
        }
        
        self.invocation.buffer.lines.removeAllObjects()
        self.invocation.buffer.lines.add(self.formatedJson)
        self.completionHandler(nil)
    }
    
    func formatElement(_ jsonElement: [String: Any]) {
        self.level += 1
        for (index, jsonKeyValue) in jsonElement.enumerated() {
            self.indent()
            if let jsonString = jsonKeyValue.value as? String {
                self.formatedJson += "\"\(jsonKeyValue.key)\" : "
                self.formatedJson += "\"\(jsonString)\""
            }
            if let jsonNumber = jsonKeyValue.value as? Double {
                self.formatedJson += "\"\(jsonKeyValue.key)\" : "
                if floor(jsonNumber) == jsonNumber {
                    self.formatedJson += "\(Int(jsonNumber))"
                }
                else {
                    self.formatedJson += "\(jsonNumber)"
                }
            }
            if let jsonBool = jsonKeyValue.value as? Bool {
                self.formatedJson += "\"\(jsonKeyValue.key)\" : "
                self.formatedJson += "\(jsonBool)"
            }
            else if let jsonObject = jsonKeyValue.value as? [String: Any] {
                self.formatedJson += "\"\(jsonKeyValue.key)\" : {\n"
                self.formatElement(jsonObject)
                self.formatedJson += "\n"
                self.indent()
                self.formatedJson += "}"
            }
            else if let jsonArray = jsonKeyValue.value as? [[String: Any]] {
                self.formatedJson += "\"\(jsonKeyValue.key)\" : [\n"
                self.level += 1
                self.indent()
                for (index, jsonKeyValue) in jsonArray.enumerated() {
                    self.formatedJson += "{\n"
                    self.formatElement(jsonKeyValue)
                    self.formatedJson += "\n"
                    self.indent()
                    self.formatedJson += "}"
                    if index + 1 < jsonArray.count {
                        self.formatedJson += ",\n"
                        self.indent()
                    }
                }
                self.formatedJson += "\n"
                self.level -= 1
                self.indent()
                self.formatedJson += "]"
            }
            if index + 1 < jsonElement.count {self.formatedJson += ",\n"}
        }
        self.level -= 1
    }
    
    func indent(str: String = " ") {
        for _ in 0..<self.level*4 {
            self.formatedJson += str
        }
    }
}

