using UnityEngine;

[ExecuteInEditMode]
public class PostProcessImage2 : MonoBehaviour
{
    public Material postProcessMaterial;

    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {

    }

    // Update is called once per frame
    void Update()
    {

    }

    void OnRenderImage(RenderTexture src, RenderTexture dest)
    {
        Graphics.Blit(src, dest, postProcessMaterial);

    }
}
