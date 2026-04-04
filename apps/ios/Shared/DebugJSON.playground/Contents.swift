import Zero

let s =
"""
{}
"""
let json = getJSONDecoder()
let d = s.data(using: .utf8)!
print (try! json.decode(APIResponse.self, from: d))
