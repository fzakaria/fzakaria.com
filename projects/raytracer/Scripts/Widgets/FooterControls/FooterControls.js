//
//  iWeb - FooterControls.js
//  Copyright (c) 2007-2008 Apple Inc. All rights reserved.
//

var FooterControls=Class.create(Widget,{widgetIdentifier:"com-apple-iweb-widget-footercontrols",initialize:function($super,instanceID,widgetPath,sharedPath,sitePath,preferences,runningInApp)
{if(instanceID!=null)
{$super(instanceID,widgetPath,sharedPath,sitePath,preferences,runningInApp);NotificationCenter.addObserver(this,FooterControls.prototype.p_handlePaginationContentsNotification,"paginationSpanContents",this.p_mediaGridID());this.updateFromPreferences();}},onload:function()
{if(this.preferences&&this.preferences.postNotification)
{this.preferences.postNotification("BLWidgetIsSafeToDrawNotification",1);}},onunload:function()
{},updateFromPreferences:function()
{this.setPage(0);},changedPreferenceForKey:function(key)
{if(this.runningInApp)
{if(key=="x-paginationSpanContents")
{this.p_setPaginationControls(this.p_paginationSpanContents());}}},prevPage:function()
{if(this.runningInApp)
{this.setPreferenceForKey(null,"x-previousPage");}
else
{NotificationCenter.postNotification(new IWNotification("PreviousPage",this.p_mediaGridID(),null));}},nextPage:function()
{if(this.runningInApp)
{this.setPreferenceForKey(null,"x-nextPage");}
else
{NotificationCenter.postNotification(new IWNotification("NextPage",this.p_mediaGridID(),null));}},setPage:function(pageIndex)
{if(this.runningInApp)
{this.setPreferenceForKey(pageIndex,"x-setPage");}
else
{NotificationCenter.postNotification(new IWNotification("SetPage",this.p_mediaGridID(),{pageIndex:pageIndex}));}},p_mediaGridID:function()
{var mediaGridID=null;if(this.preferences)
{mediaGridID=this.preferenceForKey("gridID");}
if(mediaGridID===undefined)
{mediaGridID=null;}
return mediaGridID;},p_paginationSpanContents:function()
{var paginationSpanContents=null;if(this.preferences)
{paginationSpanContents=this.preferenceForKey("x-paginationSpanContents");}
if(paginationSpanContents===undefined)
{paginationSpanContents=null;}
return paginationSpanContents;},p_handlePaginationContentsNotification:function(notification)
{var userInfo=notification.userInfo();var controls=userInfo.controls||"";this.p_setPaginationControls(controls);},p_setPaginationControls:function(controls)
{var template=new Template(controls);var myControls=template.evaluate({WIDGET_ID:this.instanceID});this.getElementById("pagination_controls").update(myControls);}});