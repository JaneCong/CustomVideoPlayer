//
//  LGVideoRenderView.m
//  CustomAVPlayer
//
//  Created by L了个G on 2017/12/18.
//  Copyright © 2017年 L了个G. All rights reserved.
//

#import "LGVideoRenderView.h"
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

// Uniform index.
enum
{
    UNIFORM_Y,
    UNIFORM_UV,
    UNIFORM_RGBA,
    UNIFORM_ISYUV,
    UNIFORM_LUMA_THRESHOLD,
    UNIFORM_CHROMA_THRESHOLD,
    UNIFORM_ROTATION_ANGLE,
    UNIFORM_COLOR_CONVERSION_MATRIX,
    NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];

// Color Conversion Constants (YUV to RGB) including adjustment from 16-235/16-240 (video range)

// BT.601, which is the standard for SDTV.
static const GLfloat kColorConversion601[] = {
    1.164,  1.164, 1.164,
    0.0, -0.392, 2.017,
    1.596, -0.813,   0.0,
};

// BT.709, which is the standard for HDTV.
static const GLfloat kColorConversion709[] = {
    1.164,  1.164, 1.164,
    0.0, -0.213, 2.112,
    1.793, -0.533,   0.0,
};
@interface LGVideoRenderView(){
    const GLfloat *_preferredConversion;
}
@property (nonatomic) GLuint program;
@property (nonatomic) EAGLContext *context;
@property (nonatomic) GLuint renderBuffer;
@property (nonatomic) GLuint frameBuffer;
@property (nonatomic) CAEAGLLayer *rendLayer;

@property (nonatomic) CVOpenGLESTextureCacheRef videoTextureCache;
@property (nonatomic) CVOpenGLESTextureRef lumaTexture;
@property (nonatomic) CVOpenGLESTextureRef chreomaTexture;
@property (nonatomic) CVOpenGLESTextureRef rgbaTexture;
@end

@implementation LGVideoRenderView


-(void)setUpGLParams
{
    [self setUpLayer];
    [self setUpContext];
    [self setUpRenderBufferAndFrameBuffer];
    [self setViewPort];
    [self compileAndLinkShader];
    [self setShaderParams];
    [self configCoreVideoParams];
}

+(Class)layerClass
{
    return [CAEAGLLayer class];
}

-(void)setUpLayer{
    self.rendLayer = (CAEAGLLayer *)self.layer;
    self.rendLayer.opaque = YES;
    self.rendLayer.drawableProperties = @{ kEAGLDrawablePropertyRetainedBacking :[NSNumber numberWithBool:NO],
                                           kEAGLDrawablePropertyColorFormat : kEAGLColorFormatRGBA8};
}

-(void)setUpContext{
    
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (![EAGLContext setCurrentContext:self.context]) {
        NSLog(@"set current context failed");
    }
}

-(void)setUpRenderBufferAndFrameBuffer{
    if (self.renderBuffer) {
        glDeleteRenderbuffers(1, &_renderBuffer);
        self.renderBuffer = 0;
    }
    
    if (self.frameBuffer) {
        glDeleteFramebuffers(1, &_frameBuffer);
        self.frameBuffer = 0;
    }
    GLuint renderBuffer,frameBuffer;
    glGenRenderbuffers(1, &renderBuffer);
    self.renderBuffer = renderBuffer;
    glBindRenderbuffer(GL_RENDERBUFFER, self.renderBuffer);
    [self.context renderbufferStorage:GL_RENDERBUFFER fromDrawable:self.rendLayer];
    
    glGenFramebuffers(1, &frameBuffer);
    self.frameBuffer = frameBuffer;
    glBindFramebuffer(GL_FRAMEBUFFER, self.frameBuffer);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, self.renderBuffer);
}

-(void)setViewPort{
    //CGFloat scale = [[UIScreen mainScreen] scale]; //获取视图放大倍数，可以把scale设置为1试试
    glViewport(0, 0, [UIScreen mainScreen].bounds.size.width , [UIScreen mainScreen].bounds.size.height);
}

-(void)compileAndLinkShader{
    NSString *vertFile = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"vsh"];
    NSString *fragFile = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"fsh"];
    
    GLuint vertSahder,fragShader;
    GLuint program = glCreateProgram();
    [self compileShader:&vertSahder type:GL_VERTEX_SHADER file:vertFile];
    [self compileShader:&fragShader type:GL_FRAGMENT_SHADER file:fragFile];
    
    glAttachShader(program, vertSahder);
    glAttachShader(program, fragShader);
    
    glDeleteShader(vertSahder);
    glDeleteShader(fragShader);
    self.program = program;
    
    glLinkProgram(self.program);
    GLint linkSuccess;
    glGetProgramiv(self.program, GL_LINK_STATUS, &linkSuccess);
    if (linkSuccess == GL_FALSE) { //连接错误
        GLchar messages[256];
        glGetProgramInfoLog(self.program, sizeof(messages), 0, &messages[0]);
        NSString *messageString = [NSString stringWithUTF8String:messages];
        NSLog(@"error%@", messageString);
        return ;
    }
    else {
        NSLog(@"link ok");
        glUseProgram(self.program); //成功便使用，避免由于未使用导致的的bug
    }
}

-(void)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file{
    NSString *content = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
    const GLchar* source = (GLchar *)[content UTF8String];
    
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);
}

-(void)setShaderParams{
    uniforms[UNIFORM_Y] = glGetUniformLocation(self.program, "SamplerY");
    uniforms[UNIFORM_UV] = glGetUniformLocation(self.program, "SamplerUV");
    uniforms[UNIFORM_RGBA] = glGetUniformLocation(self.program, "SamplerRGBA");
    uniforms[UNIFORM_LUMA_THRESHOLD] = glGetUniformLocation(self.program, "lumaThreshold");
    uniforms[UNIFORM_CHROMA_THRESHOLD] = glGetUniformLocation(self.program, "chromaThreshold");
    uniforms[UNIFORM_ROTATION_ANGLE] = glGetUniformLocation(self.program, "preferredRotation");
    uniforms[UNIFORM_COLOR_CONVERSION_MATRIX] = glGetUniformLocation(self.program, "colorConversionMatrix");
    uniforms[UNIFORM_ISYUV] = glGetUniformLocation(self.program, "isYUV");
    glUniform1i(uniforms[UNIFORM_Y], 0);
    glUniform1i(uniforms[UNIFORM_UV], 1);
    glUniform1i(uniforms[UNIFORM_RGBA], 2);
    glUniform1f(uniforms[UNIFORM_LUMA_THRESHOLD], 1.0);
    glUniform1f(uniforms[UNIFORM_CHROMA_THRESHOLD], 1.0);
//    glUniform1f(uniforms[UNIFORM_ROTATION_ANGLE], self.preferredRotation);

}

-(void)configCoreVideoParams{
    CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, self.context, NULL, &_videoTextureCache);
    if (err != noErr) {
        NSLog(@"Error at CVOpenGLESTextureCacheCreate %d",err);
        return;
    }
}

-(void)rendYUVPixbuffer:(CVPixelBufferRef)buffer
{
  
    CVReturn err;
    if (buffer != NULL) {
        int frameWidth = (int)CVPixelBufferGetWidth(buffer);
        int frameHeight= (int)CVPixelBufferGetHeight(buffer);
        
        if (!_videoTextureCache) {
            NSLog(@"No Video texture cache");
            return;
        }
        
        [self cleanUpTextures];
        
        
        /*
         Use the color attachment of the pixel buffer to determine the appropriate color conversion matrix.
         */
        CFTypeRef colorAttachments = CVBufferGetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, NULL);
        
        if (colorAttachments == kCVImageBufferYCbCrMatrix_ITU_R_601_4) {
            _preferredConversion = kColorConversion601;
        }
        else {
            _preferredConversion = kColorConversion709;
        }
        
        /*
         CVOpenGLESTextureCacheCreateTextureFromImage will create GLES texture optimally from CVPixelBufferRef.
         */
        
        /*
         Create Y and UV textures from the pixel buffer. These textures will be drawn on the frame buffer Y-plane.
         */
        
        glActiveTexture(GL_TEXTURE0);
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _videoTextureCache,
                                                           buffer,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_RED_EXT,
                                                           frameWidth,
                                                           frameHeight,
                                                           GL_RED_EXT,
                                                           GL_UNSIGNED_BYTE,
                                                           0,
                                                           &_lumaTexture);
        if (err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        
        glBindTexture(CVOpenGLESTextureGetTarget(_lumaTexture), CVOpenGLESTextureGetName(_lumaTexture));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        // UV-plane.
        glActiveTexture(GL_TEXTURE1);
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _videoTextureCache,
                                                           buffer,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_RG_EXT,
                                                           frameWidth / 2,
                                                           frameHeight / 2,
                                                           GL_RG_EXT,
                                                           GL_UNSIGNED_BYTE,
                                                           1,
                                                           &_chreomaTexture);
        if (err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        
        glBindTexture(CVOpenGLESTextureGetTarget(_chreomaTexture), CVOpenGLESTextureGetName(_chreomaTexture));
        NSLog(@"id %d", CVOpenGLESTextureGetName(_chreomaTexture));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        
//        glBindFramebuffer(GL_FRAMEBUFFER, self.frameBuffer);
//
//        // Set the view port to the entire view.
//        glViewport(0, 0, frameWidth, frameHeight);
        
    }
    
    glUniformMatrix3fv(uniforms[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, _preferredConversion);
    glUniform1f(uniforms[UNIFORM_ROTATION_ANGLE], self.preferredRotation);
    glUniform1f(uniforms[UNIFORM_ISYUV], YES);
    glClearColor(1.0, 1.0, 0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    _preferredConversion = kColorConversion601;
    //前三个是顶点坐标， 后面两个是纹理坐标
    GLfloat attrArr[] =
    {
        -1.0f, -1.0f, -1.0f,    0.0f, 1.0f,
        1.0f, -1.0f, -1.0f,     1.0f, 1.0f,
        -1.0f, 1.0f, -1.0f,     0.0f, 0.0f,
        1.0f, 1.0f, -1.0f,      1.0f, 0.0f,
    };

    GLuint attaBuffer;
    glGenBuffers(1, &attaBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, attaBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(attrArr), &attrArr, GL_DYNAMIC_DRAW);

    GLuint position = glGetAttribLocation(self.program, "position");
    GLuint textCoordinate = glGetAttribLocation(self.program, "texCoord");
    glVertexAttribPointer(position, 3, GL_FLOAT, GL_FALSE, sizeof(GLfloat) * 5, NULL);
    glEnableVertexAttribArray(position);

    glVertexAttribPointer(textCoordinate, 2, GL_FLOAT, GL_FALSE, sizeof(GLfloat) * 5, (float *)NULL + 3);
    glEnableVertexAttribArray(textCoordinate);

    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    [self.context presentRenderbuffer:GL_RENDERBUFFER];
}


- (void)cleanUpTextures
{
    if (_lumaTexture) {
        CFRelease(_lumaTexture);
        _lumaTexture = NULL;
    }
    
    if (_chreomaTexture) {
        CFRelease(_chreomaTexture);
        _chreomaTexture = NULL;
    }
    
    if (_rgbaTexture) {
        CFRelease(_rgbaTexture);
        _rgbaTexture = NULL;
    }
    // Periodic texture cache flush every frame
    CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
}

-(void)rendRGBPixbuffer:(CVPixelBufferRef)buffer
{
    CVReturn err;
    if (buffer != NULL) {
        int frameWidth = (int)CVPixelBufferGetWidth(buffer);
        int frameHeight= (int)CVPixelBufferGetHeight(buffer);
        
        if (!_videoTextureCache) {
            NSLog(@"No Video texture cache");
            return;
        }
        
        [self cleanUpTextures];
        
        
        glActiveTexture(GL_TEXTURE2);
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _videoTextureCache,
                                                           buffer,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_RGBA,
                                                           frameWidth,
                                                           frameHeight,
                                                           GL_RGBA,
                                                           GL_UNSIGNED_BYTE,
                                                           0,
                                                           &_rgbaTexture);
        if (err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        
        glBindTexture(CVOpenGLESTextureGetTarget(_rgbaTexture), CVOpenGLESTextureGetName(_rgbaTexture));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
   
        
        
        //        glBindFramebuffer(GL_FRAMEBUFFER, self.frameBuffer);
        //
        //        // Set the view port to the entire view.
        //        glViewport(0, 0, frameWidth, frameHeight);
        
    }

   // glUniform1f(uniforms[UNIFORM_ROTATION_ANGLE], self.preferredRotation);
    glUniform1f(uniforms[UNIFORM_ISYUV], NO);
    glClearColor(1.0, 1.0, 0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    //前三个是顶点坐标， 后面两个是纹理坐标
    GLfloat attrArr[] =
    {
        -1.0f, -1.0f, -1.0f,    0.0f, 1.0f,
        1.0f, -1.0f, -1.0f,     1.0f, 1.0f,
        -1.0f, 1.0f, -1.0f,     0.0f, 0.0f,
        1.0f, 1.0f, -1.0f,      1.0f, 0.0f,
    };
    
    GLuint attaBuffer;
    glGenBuffers(1, &attaBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, attaBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(attrArr), &attrArr, GL_DYNAMIC_DRAW);
    
    GLuint position = glGetAttribLocation(self.program, "position");
    GLuint textCoordinate = glGetAttribLocation(self.program, "texCoord");
    glVertexAttribPointer(position, 3, GL_FLOAT, GL_FALSE, sizeof(GLfloat) * 5, NULL);
    glEnableVertexAttribArray(position);
    
    glVertexAttribPointer(textCoordinate, 2, GL_FLOAT, GL_FALSE, sizeof(GLfloat) * 5, (float *)NULL + 3);
    glEnableVertexAttribArray(textCoordinate);
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    [self.context presentRenderbuffer:GL_RENDERBUFFER];
}



@end
