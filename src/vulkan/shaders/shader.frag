#version 450

layout(location = 0) in vec3 fragColor;
layout(location = 1) in vec2 fragTexCoord;

layout(binding = 0) uniform sampler2D texSampler;

layout(location = 0) out vec4 outColor;

layout(push_constant) uniform PushConstants {
    uint useTexture;
} pc;

void main() {
    if (pc.useTexture == 1) {
        vec4 texColor = texture(texSampler, fragTexCoord);
        outColor = texColor * vec4(fragColor, 1.0);
    } else {
        outColor = vec4(fragColor, 1.0);
    }
}
