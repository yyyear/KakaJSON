//
//  Convertible.swift
//  KakaJSON
//
//  Created by MJ Lee on 2019/8/11.
//  Copyright © 2019 MJ Lee. All rights reserved.
//

import Foundation

// MARK: - Convertible Interface
public protocol ModelPropertyKey {}
extension String: ModelPropertyKey {}
extension Array: ModelPropertyKey where Element == String {}

public typealias JSONPropertyKey = String

public protocol Convertible {
    init()
    
    /// Get a key from propertyName when converting from JSON to model
    ///
    /// Only call once for every property in every type
    func kk_modelKey(from property: Property) -> ModelPropertyKey
    
    /// Get a model modelValue from jsonValue when converting from JSON to model
    ///
    /// - Returns: return `nil` indicates ignore the property,
    /// use the initial value instead.
    /// return `JSONValue` indicates do nothing
    func kk_modelValue(from jsonValue: Any?,
                       _ property: Property) -> Any?
    
    /// model type for Any、AnyObject、Convertible...
    func kk_modelType(from jsonValue: Any?,
                      _ property: Property) -> Convertible.Type?
    
    /// call when will begin to convert from JSON to model
    mutating func kk_willConvertToModel(from json: [String: Any])
    
    /// call when did finish converting from JSON to model
    mutating func kk_didConvertToModel(from json: [String: Any])
    
    /// Get a key from propertyName when converting from model to JSON
    ///
    /// Only call once for every property in every type
    func kk_JSONKey(from property: Property) -> JSONPropertyKey
    
    /// Get a JSONValue from modelValue when converting from JSON to model
    ///
    /// - Returns: return `nil` indicates ignore the JSONValue.
    /// return `modelValue` indicates do nothing
    func kk_JSONValue(from modelValue: Any?,
                      _ property: Property) -> Any?
    
    /// call when will begin to convert from model to JSON
    func kk_willConvertToJSON()
    
    /// call when did finish converting from model to JSON
    func kk_didConvertToJSON(json: [String: Any]?)
}

public extension Convertible {
    func kk_modelKey(from property: Property) -> ModelPropertyKey {
        return ConvertibleConfig.modelKey(from: property, Self.self)
    }
    func kk_modelValue(from jsonValue: Any?,
                       _ property: Property) -> Any? {
        return ConvertibleConfig.modelValue(from: jsonValue, property, Self.self)
    }
    func kk_modelType(from jsonValue: Any?,
                      _ property: Property) -> Convertible.Type? { return nil }
    func kk_willConvertToModel(from json: [String: Any]) {}
    func kk_didConvertToModel(from json: [String: Any]) {}
    
    func kk_JSONKey(from property: Property) -> JSONPropertyKey {
        return ConvertibleConfig.JSONKey(from: property, Self.self)
    }
    func kk_JSONValue(from modelValue: Any?,
                      _ property: Property) -> Any? {
        return ConvertibleConfig.JSONValue(from: modelValue, property, Self.self)
    }
    func kk_willConvertToJSON() {}
    func kk_didConvertToJSON(json: [String: Any]?) {}
}

// MARK: - Wrapper for Convertible
public extension Convertible {
    static var kk: ConvertibleKK<Self>.Type {
        get { return ConvertibleKK<Self>.self }
        set {}
    }
    var kk: ConvertibleKK<Self> {
        get { return ConvertibleKK(self) }
        set {}
    }
    
    /// mutable version of kk
    var kk_m: ConvertibleKK_M<Self> {
        mutating get { return ConvertibleKK_M(&self) }
        set {}
    }
}

public struct ConvertibleKK_M<T: Convertible> {
    var basePtr: UnsafeMutablePointer<T>
    init(_ basePtr: UnsafeMutablePointer<T>) {
        self.basePtr = basePtr
    }
    
    public func convert(from jsonData: Data?) {
        basePtr.pointee.kk_convert(from: jsonData)
    }
    
    public func convert(from jsonData: NSData?) {
        basePtr.pointee.kk_convert(from: jsonData as Data?)
    }
    
    public func convert(from jsonString: String?) {
        basePtr.pointee.kk_convert(from: jsonString)
    }
    
    public func convert(from jsonString: NSString?) {
        basePtr.pointee.kk_convert(from: jsonString as String?)
    }
    
    public func convert(from json: [String: Any]?) {
        basePtr.pointee.kk_convert(from: json)
    }
    
    public func convert(from json: NSDictionary?) {
        basePtr.pointee.kk_convert(from: json as? [String: Any])
    }
}

public struct ConvertibleKK<T: Convertible> {
    var base: T
    init(_ base: T) {
        self.base = base
    }
    
    public func JSONObject() -> [String: Any]? {
        return base.kk_JSONObject()
    }
    
    public func JSONString(prettyPrinted: Bool = false) -> String? {
        return base.kk_JSONString(prettyPrinted: prettyPrinted)
    }
}

private extension Convertible {
    /// get the ponter of model
    mutating func _ptr() -> UnsafeMutableRawPointer {
        return (Metadata.type(self)!.kind == .struct)
            ? withUnsafeMutablePointer(to: &self) { UnsafeMutableRawPointer($0) }
            : self ~>> UnsafeMutableRawPointer.self
    }
}

// MARK: - JSON -> Model
extension Convertible {
    mutating func kk_convert(from jsonData: Data?) {
        if let json = JSONSerialization.kk_JSON(jsonData, [String: Any].self) {
            kk_convert(from: json)
            return
        }
        Logger.error("Failed to get JSON from JSONData.")
    }
    
    mutating func kk_convert(from jsonString: String?) {
        if let json = JSONSerialization.kk_JSON(jsonString, [String: Any].self) {
            kk_convert(from: json)
            return
        }
        Logger.error("Failed to get JSON from JSONString.")
    }
    
    mutating func kk_convert(from json: [String: Any]?) {
        guard let dict = json,
            let mt = Metadata.type(self) as? ModelType,
            let properties = mt.properties else { return }
        
        // get data address
        let model = _ptr()
        
        kk_willConvertToModel(from: dict)
        
        // enumerate properties
        for property in properties {
            // key filter
            let key = mt.modelKey(from: property.name,
                                  kk_modelKey(from: property))
            
            // value filter
            guard let newValue = kk_modelValue(
                from: dict.kk_value(for: key),
                property)~! else { continue }
            
            let propertyType = property.dataType
            // if they are the same type, set value directly
            if Swift.type(of: newValue) == propertyType {
                property.set(newValue, for: model)
                continue
            }
            
            // Model Type have priority
            // it can return subclass object to match superclass type
            if let modelType = kk_modelType(from: newValue, property),
                let value = _modelTypeValue(newValue, modelType, propertyType) {
                property.set(value, for: model)
                continue
            }
            
            // try to convert newValue to propertyType
            guard let value = newValue~?.kk_value(propertyType) else {
                property.set(newValue, for: model)
                continue
            }
            
            property.set(value, for: model)
        }
        
        kk_didConvertToModel(from: dict)
    }
    
    private mutating
    func _modelTypeValue(_ jsonValue: Any,
                         _ modelType: Any.Type,
                         _ propertyType: Any.Type) -> Any? {
        // don't use `propertyType is XX.Type`
        // because it may be an `Any` type
        if let json = jsonValue as? [Any],
            let models = json.kk.modelArray(anyType: modelType) {
            return propertyType is NSMutableArray.Type
                ? NSMutableArray(array: models)
                : models
        }
        
        if let json = jsonValue as? [String: Any] {
            if let jsonDict = jsonValue as? [String: [String: Any]?] {
                var modelDict = [String: Any]()
                for (k, v) in jsonDict {
                    guard let m = v?.kk.model(anyType: modelType) else { continue }
                    modelDict[k] = m
                }
                guard modelDict.count > 0 else { return jsonValue }
                
                return propertyType is NSMutableDictionary.Type
                    ? NSMutableDictionary(dictionary: modelDict)
                    : modelDict
            } else {
                return json.kk.model(anyType: modelType)
            }
        }
        return jsonValue
    }
}

// MARK: - Model -> JSON
extension Convertible {
    func kk_JSONObject() -> [String: Any]? {
        guard let mt = Metadata.type(self) as? ModelType,
            let properties = mt.properties
            else { return nil }
        
        kk_willConvertToJSON()
        
        // as AnyObject is important! for class if xx is protocol type
        // var model = xx as AnyObject
        var model = self
        
        // get data address
        let ptr = model._ptr()
        
        // get JSON from model
        var json = [String: Any]()
        for property in properties {
            // value filter
            guard let value = kk_JSONValue(
                from: property.get(from: ptr)~!,
                property)~! else { continue }
            
            guard let v = value~?.kk_JSON() else { continue }
            
            // key filter
            json[mt.JSONKey(from: property.name,
                            kk_JSONKey(from: property))] = v
        }
        
        kk_didConvertToJSON(json: json.isEmpty ? nil : json)
        
        return json
    }
    
    func kk_JSONString(prettyPrinted: Bool = false) -> String? {
        if let str = JSONSerialization.kk_string(kk_JSONObject(),
                                                 prettyPrinted: prettyPrinted) {
            return str
        }
        Logger.error("Failed to get JSONString from JSON.")
        return nil
    }
}
