Shader "Lisii/postProcess/BrokenGlass"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _GlassMask ("Glass Mask", 2D) = "white" {}
        _GlassCrack ("GlassCrack", Float) = 0.5
        _GlassNormal ("GlassNormal", 2D) = "bump" {}
        _Distort ("Distort", Range(0,10)) = 0.5
    }
    SubShader
    {
        // No culling or depth
        Cull Off
        ZWrite Off
        ZTest Always

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            sampler2D _MainTex;
            sampler2D _GlassMask;
            float4 _GlassMask_ST;
            float _GlassCrack;
            sampler2D _GlassNormal;
            float _Distort;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }


            fixed4 frag(v2f i) : SV_Target
            {
                // - 设置碎屏贴图的UV坐标
                // 计算屏幕宽高比
                float aspect = _ScreenParams.x / _ScreenParams.y;
                // 根据_ST参数调整UV坐标（缩放和平移）
                fixed2 glass_uv = i.uv * _GlassMask_ST.xy + _GlassMask_ST.zw;
                // 根据宽高比调整X轴坐标，防止拉伸
                glass_uv.x = (glass_uv.x - 0.5) * aspect + 0.5;

                // - 采样碎屏法线贴图，计算UV扰动
                fixed3 glass_normal = UnpackNormal(tex2D(_GlassNormal, glass_uv));
                fixed2 uv_distort = i.uv + glass_normal.xy * _Distort;
                // - 采样主贴图颜色，并应用碎屏效果
                fixed4 col = tex2D(_MainTex, uv_distort);
                fixed3 final_color = col.rgb;

                // - 根据碎屏遮罩贴图的灰度值，混合裂纹颜色
                half glass_opacity = tex2D(_GlassMask, glass_uv).r;
                final_color = lerp(final_color, _GlassCrack.xxx, glass_opacity);

                return fixed4(final_color, col.a);
            }
            ENDCG
        }
    }
}