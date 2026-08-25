using System.Text.Json;
using System.Text.Json.Nodes;

namespace GuardNest.Core.Firebase;

/// <summary>Translation between Firestore's typed JSON values and CLR objects.</summary>
internal static class FirestoreValues
{
    public static JsonObject EncodeFields(IReadOnlyDictionary<string, object?> fields)
    {
        var obj = new JsonObject();
        foreach (var (key, value) in fields) obj[key] = Encode(value);
        return obj;
    }

    private static JsonNode Encode(object? value) => value switch
    {
        null => new JsonObject { ["nullValue"] = null },
        bool b => new JsonObject { ["booleanValue"] = b },
        string s => new JsonObject { ["stringValue"] = s },
        int or long => new JsonObject { ["integerValue"] = Convert.ToInt64(value).ToString() },
        double or float => new JsonObject { ["doubleValue"] = Convert.ToDouble(value) },
        DateTimeOffset t => new JsonObject
        {
            ["timestampValue"] = t.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"),
        },
        IReadOnlyDictionary<string, object?> map => new JsonObject
        {
            ["mapValue"] = new JsonObject { ["fields"] = EncodeFields(map) },
        },
        IReadOnlyDictionary<string, bool> flags => new JsonObject
        {
            ["mapValue"] = new JsonObject
            {
                ["fields"] = EncodeFields(flags.ToDictionary(e => e.Key, e => (object?)e.Value)),
            },
        },
        System.Collections.IEnumerable list => EncodeList(list),
        _ => new JsonObject { ["stringValue"] = value.ToString() ?? "" },
    };

    private static JsonNode EncodeList(System.Collections.IEnumerable list)
    {
        var values = new JsonArray();
        foreach (var item in list) values.Add(Encode(item));
        return new JsonObject { ["arrayValue"] = new JsonObject { ["values"] = values } };
    }

    public static Dictionary<string, object?> DecodeFields(JsonElement document)
    {
        var result = new Dictionary<string, object?>();
        if (!document.TryGetProperty("fields", out var fields)) return result;
        foreach (var field in fields.EnumerateObject()) result[field.Name] = DecodeValue(field.Value);
        return result;
    }

    private static object? DecodeValue(JsonElement value)
    {
        foreach (var prop in value.EnumerateObject())
        {
            switch (prop.Name)
            {
                case "nullValue": return null;
                case "booleanValue": return prop.Value.GetBoolean();
                case "stringValue": return prop.Value.GetString();
                case "integerValue": return long.TryParse(prop.Value.GetString(), out var i) ? i : 0L;
                case "doubleValue": return prop.Value.GetDouble();
                case "timestampValue": return prop.Value.GetDateTimeOffset();
                case "mapValue": return DecodeFields(prop.Value);
                case "arrayValue":
                    var items = new List<object?>();
                    if (prop.Value.TryGetProperty("values", out var values))
                    {
                        foreach (var item in values.EnumerateArray()) items.Add(DecodeValue(item));
                    }
                    return items;
            }
        }
        return null;
    }
}
