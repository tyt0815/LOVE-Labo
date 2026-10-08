local Sprite = require("core.scene_component"):extend({
    componentType = "SpriteComponent",
    properties = {image = {type = "image", default = false}}
})
return Sprite
