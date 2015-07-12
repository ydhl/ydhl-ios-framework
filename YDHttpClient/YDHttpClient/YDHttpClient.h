//
//  YDHttpClient.h
//  YDHttpClient
//
//  Created by leeboo on 14-9-1.
//  Copyright (c) 2014年 ydhl. All rights reserved.
//

#import <Foundation/Foundation.h>
/**
 * @brief 缓存如何存储
 *
 * @author leeboo
 *
 */
typedef enum {
    /**
     * @brief 不缓存
     */
    CacheTypeIgnore = 1,
    /**
     * @brief 整体替换
     */
    CacheTypeReplace = 2,
    /**
     * @brief 追加在结尾
     */
    CacheTypeAppend = 3,
    /**
     * @brief 追加在开头
     */
    CacheTypePrepend = 4
}CacheType;

/**
 * @brief api调用策略
 * @author leeboo
 *
 */
typedef enum{
    /**
     * @brief 先取缓存的数据，然后在调用api, 会调用handleresult两次
     */
    FetchTypeCacheThenApi = 1,
    /**
     * @brief 先调用api，如果调用失败则取缓存，会调用handleresult一次
     */
    FetchTypeApiElseCache = 2,
    
    /**
     * @brief 直接通过api获取数据,不管api调用成功与否，不通过缓存
     */
    FetchTypeApi = 3,
    /**
     * @brief 直接通过cache获取，不调用api
     */
    FetchTypeCache = 4,
    /**
     * @brief 如果cache有，直接通过cache获取，不调用api；如果cache没有，调用api
     */
    FetchTypeCacheElseApi = 5,
    /**
     * @brief 如果cache有，直接通过cache获取 回调handleresult；同时api也调用，但api调用接口缓存起来，并不回调handleresult；如果cache不存在，调用api，并回调handleresult
     */
    FetchTypeCacheAwaysApi = 6
}FetchType;

/**
 * @brief api返回都数据格式
 * @author leeboo
 *
 */
typedef enum{
    ApiFromatJSON = 1,
    ApiFromatXML = 2
}ApiFromat;

@protocol YDHttpClientDelegate;

#pragma 回调

@protocol YDHttpClientDelegate <NSObject>

/**
 * @brief 根据what调用不同的uri
 */
-(void)callApiFor:(NSInteger)what;

/**
 * @brief 判断data中的数据是成功还是失败，成功调用onSuccess，失败调用onFail
 */
-(void)handleResult:(NSString *)data for:(NSInteger)what hasDone:(BOOL)done;

/**
 * @brief 取得用于缓存的key
 */
-(NSString *)getCacheKeyFor:(NSInteger )what;

/**
 * @brief 把from的结构追加在to的结尾，from 与 to 都不为nil
 */
-(NSString *)appendResultFrom:(NSString *)from To:(NSString *) to;

/**
 * @brief 把from的结构追加在to的开始，from 与 to 都不为nil
 */
-(NSString *)prependResultFrom:(NSString *)from To:(NSString *) to;

/**
 * @brief 检查api返回的data是否是成功调用的数据
 */
-(BOOL)isCallSuccess:(NSString *)data;

/**
 *@brief 当出现网路错误时调用
 */
-(void)onNetworkError:(NSInteger) what error:(NSString *)error;
@end

#pragma httpclients
@interface YDHttpClient : NSObject
- (id)initByFetch:(FetchType)fetchType andCache:(CacheType) cacheType;

-(void)changeFetch:(FetchType)fetchType andCache:(CacheType) cacheType;
-(void)callApi:(NSString *)uri for:(NSInteger )what by:(NSString *)method withData:(NSDictionary *)data delegate:(id<YDHttpClientDelegate>) deletage;
/**
 * @brief files中是上传文件的名字，其上传的文件在data中，为本地文件路径
 */
-(void)callApiByPost:(NSString *)uri for:(NSInteger)what withData:(NSDictionary *)data withFile:(NSArray *)files delegate:(id<YDHttpClientDelegate>)deletage;

+(NSJSONSerialization *)getJson:(NSString *)data;
+(NSString *)stringFromJSON:(NSJSONSerialization *)data;
@end
