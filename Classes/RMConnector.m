//
//  RMConnector.m
//  Hpple
//
//  Created by Frank Wittig on 06.05.10.
//  Copyright 2010 Frank Wittig <frank@lintuxhome.de>. All rights reserved.
//

#import "RMConnector.h"

@interface RMConnector (PrivateMethods)

- (void) didStart;
- (void) didFinish;
- (void) didFailWithError:(NSError*)anError;

- (ASIHTTPRequest *)requestWithURL:(NSURL *)url cookies:(NSArray *)cookies startSelector:(SEL)startSelector finishSelector:(SEL)finishSelector failSelector:(SEL)failSelector;

- (void) fetchLogin;
- (void) loginWithCookies:(NSArray *)cookies Token:(NSString *)token;

- (void) fetchMyPageWithCookies:(NSArray *)cookies;
- (void) fetchMyPageFeedsWithCookies:(NSArray *)cookies;

- (void) fetchProjectsPageWithCookies:(NSArray *)cookies;
- (void) fetchProjectsFeedWithCookies:(NSArray *)cookies;

@end

@implementation RMConnector

@synthesize urlString;
@synthesize password;
@synthesize username;
@synthesize responseDictionary;
@synthesize delegate;
@synthesize didStartSelector;
@synthesize didFinishSelector;
@synthesize didFailSelector;
@synthesize error;

#pragma mark Connector Basics
- (void) dealloc {
	[urlString release];
	[username release];
	[password release];
	
	[responseDictionary release];
	[delegate release];
	[error release];
	
	[super dealloc];
}

+ (id) connectorWithUrlString:(NSString *) url username:(NSString *) user password:(NSString *) pass {
	return [[[RMConnector alloc] initWithUrlString:url username:user password:pass] autorelease];
}

+ (id) connectorWithUrlString:(NSString *) urlString {
	return [RMConnector connectorWithUrlString:urlString username:nil password:nil];
}

- (id) initWithUrlString:(NSString *) url username:(NSString *) user password:(NSString *) pass {
	self = [super init];
	
	if (self) {
		[self setUrlString:url];
		[self setUsername:user];
		[self setPassword:pass];
		
		responseDictionary = [[NSMutableDictionary dictionary] retain];
	}
	
	return self;
}

- (void) start {
	[self didStart];
	
	if ([[self username] length] > 0 && [[self password] length] > 0)
		[self fetchLogin];
	else
		[self fetchProjectsPageWithCookies:nil];
}

- (void) cancel {
	// TODO: cancel current requests and fail with ASIRequestCancelledErrorType
}

#pragma mark Event Methods

- (void) didStart {
	// Let the delegate know we have started
	if ([self didStartSelector]  && [[self delegate] respondsToSelector:[self didStartSelector]])
		[[self delegate] performSelectorOnMainThread:[self didStartSelector] withObject:self waitUntilDone:[NSThread isMainThread]];		
}

- (void) didFinish {
	// Let the delegate know we are done
	if ([self didFinishSelector] && [[self delegate] respondsToSelector:[self didFinishSelector]])
		[[self delegate] performSelectorOnMainThread:[self didFinishSelector] withObject:self waitUntilDone:[NSThread isMainThread]];		
}

- (void) didFailWithError:(NSError*)anError {
	error = [anError retain];
	
	// Let the delegate know something went wrong
	if ([self didFailSelector] && [[self delegate] respondsToSelector:[self didFailSelector]])
		[[self delegate] performSelectorOnMainThread:[self didFailSelector] withObject:self waitUntilDone:[NSThread isMainThread]];	
}

#pragma mark Helper Methods

- (ASIHTTPRequest *)requestWithURL:(NSURL *)url cookies:(NSArray *)cookies startSelector:(SEL)startSelector finishSelector:(SEL)finishSelector failSelector:(SEL)failSelector {
	ASIHTTPRequest * request = [ASIHTTPRequest requestWithURL:url]; 
	[request setTimeOutSeconds:300];
	[request setRequestCookies:[cookies mutableCopy]];
	[request setUseKeychainPersistance:YES];
	[request setShouldPresentAuthenticationDialog:YES];
	[request setDelegate:self];
	[request setDidFinishSelector:finishSelector];
	[request setDidFailSelector:failSelector];
	[request setDidStartSelector:startSelector];	
	
	if ([[[request url] scheme] isEqualToString:@"https"]) 
		[request setValidatesSecureCertificate:NO];
	return request;
}

#pragma mark Login Methods

- (void) fetchLogin {
	NSURL * url = [NSURL URLWithString:@"login" relativeToURL:[NSURL URLWithString:[self urlString]]];
	[[self requestWithURL:url cookies:nil startSelector:@selector(fetchLoginBegan:) finishSelector:@selector(fetchLoginCompleted:) failSelector:@selector(fetchLoginFailed:)] startAsynchronous];
}

- (void) fetchLoginBegan:(ASIHTTPRequest *)aRequest {
	NSLog(@"fetching login on: %@",[aRequest url]);
}

- (void) fetchLoginFailed:(ASIHTTPRequest *)aRequest {
	NSLog(@"fetching login failed: %@",[[aRequest error] localizedDescription]);
	[self didFailWithError:[aRequest error]];
}

- (void) fetchLoginCompleted:(ASIHTTPRequest *)aRequest {
	// Extract auth token from response html and login
	TFHpple * xpathParser = [[[TFHpple alloc] initWithHTMLData:[aRequest responseData]] autorelease];
	TFHppleElement * tokenElement = [xpathParser at:@"//input[@name='authenticity_token']"];
	NSString * token = [tokenElement objectForKey:@"value"];
	[self loginWithCookies:[aRequest responseCookies] Token:token];
}

- (void) loginWithCookies:(NSArray *)cookies Token:(NSString *)token {
	NSURL * url = [NSURL URLWithString:@"login" relativeToURL:[NSURL URLWithString:[self urlString]]];
	ASIFormDataRequest * request = [ASIFormDataRequest requestWithURL:url];
	[request setTimeOutSeconds:300];
	[request setRequestCookies:[cookies mutableCopy]];
	[request setUseKeychainPersistance:YES];
	[request setShouldPresentAuthenticationDialog:YES];
	[request setDelegate:self];
	[request setDidFinishSelector:@selector(loginCompleted:)];
	[request setDidFailSelector:@selector(loginFailed:)];
	[request setDidStartSelector:@selector(loginBegan:)];	
	[request setPostValue:[self username] forKey:@"username"];
	[request setPostValue:[self password] forKey:@"password"];
	[request setPostValue:@"1" forKey:@"autologin"];
	
	if (token) 
		[request setPostValue:token forKey:@"authenticity_token"];
	
	if ([[[request url] scheme] isEqualToString:@"https"]) 
		[request setValidatesSecureCertificate:NO];
	
	[request startAsynchronous];
}

- (void) loginBegan:(ASIFormDataRequest *)aRequest {
	NSLog(@"login on: %@",[aRequest url]);
}

- (void) loginFailed:(ASIFormDataRequest *)aRequest {
	NSLog(@"login failed: %@",[[aRequest error] localizedDescription]);
	[self didFailWithError:[aRequest error]];
}

- (void) loginCompleted:(ASIFormDataRequest *)aRequest {
	NSLog(@"logged on: %@; status code: %d",[aRequest url],[aRequest responseStatusCode]);
	[self fetchMyPageWithCookies:[aRequest responseCookies]];
}

#pragma mark Fetching My Page

- (void) fetchMyPageWithCookies:(NSArray *)cookies {
	NSURL * url = [NSURL URLWithString:@"my/page" relativeToURL:[NSURL URLWithString:[self urlString]]];
	[[self requestWithURL:url cookies:cookies startSelector:@selector(fetchMyPageBegan:) finishSelector:@selector(fetchMyPageCompleted:) failSelector:@selector(fetchMyPageFailed:)] startAsynchronous];
}

- (void) fetchMyPageBegan:(ASIHTTPRequest *)aRequest {
	NSLog(@"fetching my page on: %@",[aRequest url]);
}

- (void) fetchMyPageFailed:(ASIHTTPRequest *)aRequest {
	NSLog(@"fetching my page failed: %@",[[aRequest error] localizedDescription]);
	[self didFailWithError:[aRequest error]];
}

- (void) fetchMyPageCompleted:(ASIHTTPRequest *)aRequest {
	NSArray * cookies = [aRequest responseCookies];

	// extract feed urls
	TFHpple * myPageParser = [[[TFHpple alloc] initWithHTMLData:[aRequest responseData]] autorelease];
	NSArray * feeds = [myPageParser search:@"//link[@type='application/atom+xml']"];
	NSMutableDictionary * feedDicts = [NSMutableDictionary dictionary];
	for (TFHppleElement * feed in feeds) 
	{
		NSURL * feedURL = [NSURL URLWithString:[feed objectForKey:@"href"] relativeToURL:[NSURL URLWithString:[self urlString]]];
		ASIHTTPRequest * feedRequest = [self requestWithURL:feedURL cookies:cookies startSelector:nil finishSelector:nil failSelector:nil];
		[feedRequest startSynchronous];
		cookies = [feedRequest responseCookies];
		
		if ([feedRequest error]) {
			[self didFailWithError:[feedRequest error]];
			return;
		}
		
		TFHpple * issuesParser = [[[TFHpple alloc] initWithHTMLData:[feedRequest responseData]] autorelease];
		NSArray *issuesArray = [issuesParser search:@"//feed/entry"];
		
		NSMutableDictionary * issuesDict = [NSMutableDictionary dictionary];
		for (int i = 1; i <= [issuesArray count]; i++) 
		{
			NSString * href = [[issuesParser at:[NSString stringWithFormat:@"//feed/entry[%d]/link", i]] objectForKey:@"href"];
			NSURL * issueURL = [NSURL URLWithString:href relativeToURL:[NSURL URLWithString:[self urlString]]];
			ASIHTTPRequest * issueRequest = [self requestWithURL:issueURL cookies:cookies startSelector:nil finishSelector:nil failSelector:nil];
			[issueRequest startSynchronous];
			cookies = [issueRequest responseCookies];

			if ([issueRequest error]) {
				[self didFailWithError:[issueRequest error]];
				return;
			}
			
			// creating data structure to response	
			NSMutableDictionary * issueDict = [NSMutableDictionary dictionary];
			[issueDict setValue:href forKey:@"href"];
			[issueDict setValue:[[issuesParser at:[NSString stringWithFormat:@"//feed/entry[%d]/title", i]] content]		forKey:@"title"];
			[issueDict setValue:[[issuesParser at:[NSString stringWithFormat:@"//feed/entry[%d]/updated", i]] content]		forKey:@"updated"];
			[issueDict setValue:[[issuesParser at:[NSString stringWithFormat:@"//feed/entry[%d]/author/name", i]] content]	forKey:@"author"];
			[issueDict setValue:[[issuesParser at:[NSString stringWithFormat:@"//feed/entry[%d]/author/email", i]] content]	forKey:@"email"];
			[issueDict setValue:[issueRequest responseData] forKey:@"content"];			
			[issuesDict setValue:issueDict forKey:href];
		}		
		
		// Caching into response dictionary
		NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:[feed objectForKey:@"title"],@"title",[feed objectForKey:@"href"],@"href",issuesDict,@"issues",nil];
		[feedDicts setValue:dict forKey:[feed objectForKey:@"href"]];
	}
	[responseDictionary setValue:feedDicts forKey:@"myPage"];

	[self fetchProjectsPageWithCookies:cookies];
}

#pragma mark Fetching Projects

- (void) fetchProjectsPageWithCookies:(NSArray *)cookies {
	NSURL * url = [NSURL URLWithString:@"projects" relativeToURL:[NSURL URLWithString:[self urlString]]];
	[[self requestWithURL:url cookies:cookies startSelector:@selector(fetchProjectsPageBegan:) finishSelector:@selector(fetchProjectsPageCompleted:) failSelector:@selector(fetchProjectsPageFailed:)] startAsynchronous];
}

- (void) fetchProjectsPageBegan:(ASIHTTPRequest *)aRequest {
	NSLog(@"fetching projects page on: %@",[aRequest url]);
}

- (void) fetchProjectsPageFailed:(ASIHTTPRequest *)aRequest {
	NSLog(@"fetching projects page failed: %@",[[aRequest error] localizedDescription]);
	[self didFailWithError:[aRequest error]];
}

- (void) fetchProjectsPageCompleted:(ASIHTTPRequest *)aRequest {
	// extract feed url
	TFHpple * xpathParser = [[[TFHpple alloc] initWithHTMLData:[aRequest responseData]] autorelease];
	NSString *href = [[xpathParser at:@"//a[@class='atom' or @class='feed']"] objectForKey:@"href"];
	[responseDictionary setValue:[NSMutableDictionary dictionaryWithObject:href forKey:@"href"] forKey:@"projects"];
	
	[self fetchProjectsFeedWithCookies:[aRequest responseCookies]];
}

- (void) fetchProjectsFeedWithCookies:(NSArray *)cookies {
	NSURL * url = [NSURL URLWithString:[responseDictionary valueForKeyPath:@"projects.href"] relativeToURL:[NSURL URLWithString:[self urlString]]];
	[[self requestWithURL:url cookies:cookies startSelector:@selector(fetchProjectsFeedBegan:) finishSelector:@selector(fetchProjectsFeedCompleted:) failSelector:@selector(fetchProjectsFeedFailed:)] startAsynchronous];
}

- (void) fetchProjectsFeedBegan:(ASIHTTPRequest *)aRequest {
	NSLog(@"fetching projects feed on: %@",[aRequest url]);
}

- (void) fetchProjectsFeedFailed:(ASIHTTPRequest *)aRequest {
	NSLog(@"fetching projects feed failed: %@",[[aRequest error] localizedDescription]);
	[self didFailWithError:[aRequest error]];
}

- (void) fetchProjectsFeedCompleted:(ASIHTTPRequest *)aRequest {	
	NSArray * cookies = [aRequest responseCookies];

	TFHpple * feedParser = [[[TFHpple alloc] initWithHTMLData:[aRequest responseData]] autorelease];
	NSArray * entries = [feedParser search:@"//feed/entry"];
	NSMutableDictionary * feedDicts = [NSMutableDictionary dictionary];
		
	for (int i = 1; i <= [entries count]; i++) 
	{
		NSString * href = [[feedParser at:[NSString stringWithFormat:@"//feed/entry[%d]/link", i]] objectForKey:@"href"];
		NSURL * projectURL = [NSURL URLWithString:href relativeToURL:[NSURL URLWithString:[self urlString]]];
		ASIHTTPRequest * projectRequest = [self requestWithURL:projectURL cookies:cookies startSelector:nil finishSelector:nil failSelector:nil];
		[projectRequest startSynchronous];
		cookies = [projectRequest responseCookies];
				
		if ([projectRequest error]) {
			[self didFailWithError:[projectRequest error]];
			return;
		}
		
		// Fetch activity
		NSMutableDictionary * activityDict = [NSMutableDictionary dictionary];
		TFHpple * projectParser = [[[TFHpple alloc] initWithHTMLData:[projectRequest responseData]] autorelease];
		NSString * activityLink = [[projectParser at:@"//link[@type='application/atom+xml']"] objectForKey:@"href"];
		NSURL * activityURL = [NSURL URLWithString:activityLink relativeToURL:[NSURL URLWithString:[self urlString]]];
		ASIHTTPRequest * activityRequest = [self requestWithURL:activityURL cookies:cookies startSelector:nil finishSelector:nil failSelector:nil];
		[activityRequest startSynchronous];
		cookies = [activityRequest responseCookies];
		
		if ([activityRequest error]) {
			[self didFailWithError:[activityRequest error]];
			return;
		}
		
		TFHpple * activityParser = [[[TFHpple alloc] initWithHTMLData:[activityRequest responseData]] autorelease];
		NSArray * activityEntries = [activityParser search:@"//feed/entry"];
		for (int j = 1; j <= [activityEntries count]; j++) 
		{
			NSString * issueLink = [[activityParser at:[NSString stringWithFormat:@"//feed/entry[%d]/link", j]] objectForKey:@"href"];
			NSURL * issueURL = [NSURL URLWithString:issueLink relativeToURL:[NSURL URLWithString:[self urlString]]];
			ASIHTTPRequest * issueRequest = [self requestWithURL:issueURL cookies:cookies startSelector:nil finishSelector:nil failSelector:nil];
			[issueRequest startSynchronous];
			cookies = [issueRequest responseCookies];
			
			if ([issueRequest error]) {
				[self didFailWithError:[issueRequest error]];
				return;
			}
			
			// creating data structure to response	
			NSMutableDictionary * issueDict = [NSMutableDictionary dictionary];
			[issueDict setValue:issueLink forKey:@"href"];
			[issueDict setValue:[[activityParser at:[NSString stringWithFormat:@"//feed/entry[%d]/title", j]] content]		forKey:@"title"];
			[issueDict setValue:[[activityParser at:[NSString stringWithFormat:@"//feed/entry[%d]/updated", j]] content]		forKey:@"updated"];
			[issueDict setValue:[[activityParser at:[NSString stringWithFormat:@"//feed/entry[%d]/author/name", j]] content]	forKey:@"author"];
			[issueDict setValue:[[activityParser at:[NSString stringWithFormat:@"//feed/entry[%d]/author/email", j]] content]	forKey:@"email"];
			[issueDict setValue:[issueRequest responseData] forKey:@"content"];			
			[activityDict setValue:issueDict forKey:issueLink];
		}
		
		// Fetch issues
		NSMutableDictionary * issuesDict = [NSMutableDictionary dictionary];
		NSString * issuesLink = [[projectParser at:@"//a[@class='issues']"] objectForKey:@"href"];
		NSLog(@"%@",issuesLink);
		// FIXME
	
		// creating data structure to response		
		NSMutableDictionary * dict = [NSMutableDictionary dictionary];
		[dict setValue:href			forKey:@"href"];
		[dict setValue:issuesDict	forKey:@"issues"];
		[dict setValue:activityDict forKey:@"activity"];
		[dict setValue:[[feedParser at:[NSString stringWithFormat:@"//feed/entry[%d]/title", i]] content] forKey:@"title"];
		[dict setValue:[[feedParser at:[NSString stringWithFormat:@"//feed/entry[%d]/updated", i]] content] forKey:@"updated"];
		[dict setValue:[[feedParser at:[NSString stringWithFormat:@"//feed/entry[%d]/content", i]] content] forKey:@"content"];
		[feedDicts setValue:dict forKey:href];
	}
	
	[responseDictionary setValue:feedDicts forKeyPath:@"projects.content"];
	
	[self didFinish];
}

/* 
 - (NSURL *) urlProjectIssuesFeedWithUrlString:(NSString *) url {
	if ([projectIssueFeedUrls valueForKey:url])
		return [NSURL URLWithString:[projectIssueFeedUrls valueForKey:url]];
	
	NSURL *projectUrl = [NSURL URLWithString:url];
	
	NSData *data = [self dataWithUrl:projectUrl];
	TFHpple *xpathParser = [[TFHpple alloc] initWithHTMLData:data];
	
	NSString *href = [[xpathParser at:@"//a[@class='issues']"] objectForKey:@"href"];
	NSURL *issuesUrl = [[NSURL URLWithString:href relativeToURL:projectUrl] absoluteURL];
	
	data = [self dataWithUrl:issuesUrl];
	xpathParser = [[TFHpple alloc] initWithHTMLData:data];
	
	href = [[xpathParser at:@"//link[@type='application/atom+xml']"] objectForKey:@"href"];
	NSURL *feedUrl = [[NSURL URLWithString:href relativeToURL:issuesUrl] absoluteURL];
	
	[projectIssueFeedUrls setValue:[feedUrl absoluteString] forKey:url];
	
	[xpathParser release];
	return feedUrl;	
}

- (NSURL *) urlProjectActivityFeedWithUrlString:(NSString *) url {
	if ([projectActivityFeedUrls valueForKey:url])
		return [NSURL URLWithString:[projectActivityFeedUrls valueForKey:url]];

	NSURL *projectUrl = [NSURL URLWithString:url];
	
	NSData *data = [self dataWithUrl:projectUrl];
	TFHpple *xpathParser = [[TFHpple alloc] initWithHTMLData:data];
	
	TFHppleElement *element = [xpathParser at:@"//link[@type='application/atom+xml']"];
	NSString *href = [element objectForKey:@"href"];
	
	NSURL *feedUrl = [[NSURL URLWithString:href] absoluteURL];
	
	[projectActivityFeedUrls setValue:[feedUrl absoluteString] forKey:url];
	
	[xpathParser release];
	return feedUrl;
}

*/

@end
