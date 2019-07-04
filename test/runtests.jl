using WGLMakie, AbstractPlotting, WebIO, JSCall
scene = scatter(rand(4))

three = WGLMakie.three_scene(scene)

js_scene, cam = WGLMakie.to_jsscene(three, scene)

plot = js_scene.getObjectByName("scatter")
plot.position

function test(x)
    if ispressed(x, Mouse.left)
        @show pick(scene, scene.events.mouseposition[])
    end
end
on(test, scene.events.mousebuttons)
