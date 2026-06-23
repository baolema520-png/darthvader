#include <metal_stdlib>
using namespace metal;

struct FullscreenVertexIn {
    float2 position [[attribute(0)]];
    float2 uv [[attribute(1)]];
};

struct FullscreenVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex FullscreenVertexOut fullScreenCopyVertex(
    FullscreenVertexIn in [[stage_in]]
) {
    FullscreenVertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.uv = in.uv;
    return out;
}

fragment float4 copyFragment(
    FullscreenVertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler texSampler [[sampler(0)]]
) {
    return sourceTexture.sample(texSampler, in.uv);
}

struct MeshVertexIn {
    float3 clipPosition [[attribute(0)]];
    float2 uv [[attribute(1)]];
    float alpha [[attribute(2)]];
};

struct MeshVertexOut {
    float4 position [[position]];
    float2 uv;
    float alpha;
};

struct FeatureUniforms {
    float4 tint;
    float strength;
};

vertex MeshVertexOut avatarMeshVertex(
    MeshVertexIn in [[stage_in]]
) {
    MeshVertexOut out;
    out.position = float4(in.clipPosition, 1.0);
    out.uv = in.uv;
    out.alpha = in.alpha;
    return out;
}

fragment float4 avatarMeshFragment(
    MeshVertexOut in [[stage_in]],
    texture2d<float> avatarTexture [[texture(0)]],
    sampler texSampler [[sampler(0)]]
) {
    float4 color = avatarTexture.sample(texSampler, in.uv);
    color.a *= in.alpha;
    return color;
}

fragment float4 avatarFeatureFragment(
    MeshVertexOut in [[stage_in]],
    texture2d<float> avatarTexture [[texture(0)]],
    sampler texSampler [[sampler(0)]],
    constant FeatureUniforms& uniforms [[buffer(0)]]
) {
    float4 color = avatarTexture.sample(texSampler, in.uv);
    float3 tinted = mix(color.rgb, uniforms.tint.rgb, uniforms.strength);
    color.rgb = tinted;
    color.a *= in.alpha * uniforms.tint.a;
    return color;
}

fragment float4 featureSolidFragment(
    MeshVertexOut in [[stage_in]],
    constant FeatureUniforms& uniforms [[buffer(0)]]
) {
    return float4(uniforms.tint.rgb, in.alpha * uniforms.tint.a);
}
