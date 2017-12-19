//
//  LGVideoRenderView.h
//  CustomAVPlayer
//
//  Created by L了个G on 2017/12/18.
//  Copyright © 2017年 L了个G. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface LGVideoRenderView : UIView
@property (nonatomic) GLfloat preferredRotation;
@property (nonatomic) CGSize presentationRect;
-(void)setUpGLParams;

-(void)rendYUVPixbuffer:(CVPixelBufferRef)buffer;

-(void)rendRGBPixbuffer:(CVPixelBufferRef)buffer;

@end
