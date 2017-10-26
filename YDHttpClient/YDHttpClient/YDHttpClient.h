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
     * @brief 整体替换, 会把服务器返回的结果整体替换掉getCacheKeyFor:为key的缓存; 缓存的结果是请求返回的整个内容
     */
    CacheTypeReplace = 2,
    /**
     * @brief 自定义处理，将会调用handleCache方法进行处理
     */
    CacheTypeCustom = 3
}CacheType;

/**
 * @brief api调用策略
 * @author leeboo
 *
 */
typedef enum{
    /**
     * @brief get请求时：先取缓存的数据，然后在调用api, 会调用handleresult两次；post等提交请求无效
     */
    FetchTypeCacheThenApi = 1,
    /**
     * @brief get请求时：先调用api，如果调用失败则取缓存，会调用handleresult一次；post等提交请求无效
     */
    FetchTypeApiElseCache = 2,
    
    /**
     * @brief get请求时：直接通过api获取数据,不管api调用成功与否，不通过缓存；post等提交请求无效
     */
    FetchTypeApi = 3,
    /**
     * @brief get请求时：直接通过cache获取，不调用api；post等提交请求无效
     */
    FetchTypeCache = 4,
    /**
     * @brief get请求时：如果cache有，直接通过cache获取，不调用api；如果cache没有，调用api；post等提交请求无效
     */
    FetchTypeCacheElseApi = 5,
    /**
     * @brief get请求时：如果cache有，直接通过cache获取 回调handleresult；同时api也调用，但api调用接口缓存起来，并不回调handleresult；如果cache不存在，调用api，并回调handleresult；post等提交请求无效
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
 * @brief API掉通时总是会进入该方法，但是要考虑3种情况
 * api调用成功有两种情况：
 * 
 * 1. 正常调用成功
 *
 * 2. 设定的缓存策略满足条件是调用
 *
 * 3. Api调通了，但是服务端有错误，没有内容返回（比如，500错误，404等），这时data为@""
 *
 * 可通过isCallSuccess:data判断数据是成功还是失败，该方法在UI主线程中执行
 */
-(void)handleResult:(NSString *)data for:(NSInteger)what hasDone:(BOOL)done;

/*!
 * @brief 取得用于缓存的key, what标示了是什么请求，返回nil表示不缓存
 */
-(NSString *)getCacheKeyFor:(NSInteger )what;

/*!
 * @brief 把新数据newData合并到就数据oldCache中去，如果旧数据没有则传入nil；
 *
 * newData是api返回的原始数据，oldCache是之前保存的缓存数据，自行根据api的格式合并数据
 *
 * 对任何请求配置了CacheTypeCustom策略会进入handleCache
 *
 *  1）get请求时会把得到的结果传入handleCache；
 *
 *  2）非get请求，当网络错误时，也把提交的数据作为newData传入handleCache，如果需要可以把数据进行本地缓存，方便时再次提交；这时缓存的key也是通过getCacheKeyFor得到；这时的newData是调用callApi传入的Dictionay data
 * 
 *  3) 非get请求，请求的结果不会进行缓存
 *
 * 该方法不是在ui主线程执行
 */
-(NSString *)handleCache:(id)newData ToCache:(NSString *) oldCache For:(NSInteger)what;


/**
 * @brief 检查api返回的data是否是成功调用的数据
 */
-(BOOL)isCallSuccess:(NSString *)data;

/**
 *@brief 该方法总是在出现网路错误时调用（网络通时，总是会进入handleResult方法），该方法在UI主线程中执行；但进入该方法时，肯定是出现了网络异常
 */
-(void)onNetworkError:(NSInteger) what error:(NSString *)error;
@end

#pragma mark - YDHttpClient

@interface YDHttpClient : NSObject
/**
 * @brief 清除缓存到本地的cookie
 */
- (void)clearCookie;

/**
 * @brief 清除所有缓存数据，
 */
- (void)clearAllCache;
- (void)setHeader:(NSString *)header forName:(NSString *)name;
- (id)initByFetch:(FetchType)fetchType andCache:(CacheType) cacheType;
/**
 * @brief 直接通过key获取缓存中的数据，并返回,没有缓存数据则返回nil; 如果不知道key，使用fetchCacheFor: delegate
 */
-(NSString *)fetchCacheFor:(NSString *)key;
/**
 * @brief 直接获取缓存中的数据，并返回,没有缓存数据则返回nil;
 */
-(NSString *)fetchCacheFor:(NSInteger )what delegate:(id<YDHttpClientDelegate>)deletage;
/**
 * @brief 直接修改缓存的数据，key也通过getCahceKeyFor得到;如果key存在则更新，如果key不存在则插入, 如果data=nil则删除key
 */
-(void)saveCache:(NSString *)data For:(NSInteger )what delegate:(id<YDHttpClientDelegate>)deletage;

-(void)changeFetch:(FetchType)fetchType andCache:(CacheType) cacheType;
/**
 * @brief application/x-www-form-urlencoded的方式上传post，get的方式参数会url encode；请求处理是异步的
 */
-(void)callApi:(NSString *)uri for:(NSInteger )what by:(NSString *)method withData:(NSDictionary *)data delegate:(id<YDHttpClientDelegate>) deletage;
/**
 * @brief files中是上传文件的名字，其上传的文件在data中，为本地文件路径；请求处理是异步的
 */
-(void)callApiByPost:(NSString *)uri for:(NSInteger)what withData:(NSDictionary *)data withFile:(NSArray *)files delegate:(id<YDHttpClientDelegate>)deletage;

+(NSJSONSerialization *)getJson:(NSString *)data;
+(NSString *)stringFromJSON:(NSJSONSerialization *)data;
@end
