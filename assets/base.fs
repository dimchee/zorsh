#version 300 es

precision mediump float;

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec3 fragNormal;
in vec3 fragPosition;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;

uniform vec3 lightPos;
uniform vec3 viewPos;

// Output fragment color
out vec4 finalColor;

// NOTE: Add here your custom variables

void main()
{
    vec4 texelColor = texture(texture0, fragTexCoord);

    float distance    = length(lightPos - fragPosition);
    float attenuation = 1.0 / (1.0 + 0.09 * distance + 0.032 * (distance * distance));    
    // ambient
    // vec3 ambient = 0.05 * texelColor.rgb;
    // vec3 ambient = vec3(0.0);
    // diffuse
    vec3 lightDir = normalize(lightPos - fragPosition);
    vec3 normal = normalize(fragNormal);
    float diff = max(dot(lightDir, normal), 0.0);
    vec3 diffuse = diff * texelColor.rgb;
    // // specular
    // vec3 viewDir = normalize(viewPos - fragPosition);
    // vec3 reflectDir = reflect(-lightDir, normal);
    // vec3 halfwayDir = normalize(lightDir + viewDir);  
    // float spec = pow(max(dot(normal, halfwayDir), 0.0), 32.0);
    // vec3 specular = vec3(0.3) * spec; // assuming bright white light color
    // specular = vec3(0);

    finalColor = vec4(diffuse * attenuation, 1.0)*colDiffuse;
}
