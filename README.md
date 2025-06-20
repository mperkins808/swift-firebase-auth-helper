# FirebaseAuthHelper 


An elegant way to send authenticated requests from users to your servers


## Installing 

Just add the Github url in swift package manager 

```
https://github.com/mperkins808/swift-firebase-auth-helper
```

```
import FirebaseAuthHelper
```

I also recommend installing [Datastore](https://github.com/mperkins808/swift-datastore) for the helper functions that will parse the data responses


## Usage 

There are 4 main functions to be used, the authenticated functions simple wrap the basic functions


**A Simple Request with no body** 

```swift

struct healthy : Codable {
    var message: String
}

let url = "http://192.168.20.22:3000/healthy"

FirebaseAuthHelper.SimpleRequest(endpoint: url, method: .get) { resp in
    switch resp.status {
    case .ERROR:
        print(resp.message)
    case .OK:
        if let data = resp.data, let obj = Datastore.jsonDecode(data, as: healthy.self).obj {
            print(obj.message)
        }

    }
}

```

**A Simple request with a body attached, both json and form are supported currently**

data just needs to conform to Codable

```swift 

struct Response : Codable {
    var response: String
    var metadata: Metadata
}

let body = ["text": text, "id": id]
let url = "http://192.168.20.22:3000/query"

FirebaseAuthHelper.BodyRequest(endpoint: url, data: body, contentType: .json, method: .post) { resp in
    if resp.status != .OK {
        // optionally unpack resp.data here if you want to read the response body 
        print(resp.message)
        return
    }
    if let data = resp.data, let obj = Datastore.jsonDecode(data, as: Response.self).obj {
        // unpacked and ready to use!
    }    
}
```

**A Firebase authenticated simple request** 

Before you use this, you need to have completed the standard firebase boilerplate, this includes creating a firebase project and allowing users to sign in your app.


These functions are simply a wrapper for the above functions, adding the user's bearer token to the Authentication header in the request

```swift
FirebaseAuthHelper.SimpleAuthedRequest(endpoint: url, method: .get) { resp in 
    ... 
}

FirebaseAuthHelper.AuthedBodyRequest(endpoint:url, method: .post, data: body, contentType: .json) { resp in 
    ... 
}
```

