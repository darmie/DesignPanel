package core.service
{
	import com.adobe.serialization.json.JSON;
	
	import flash.display.BitmapData;
	import flash.display.DisplayObject;
	import flash.display.MovieClip;
	import flash.geom.Matrix;
	import flash.geom.Rectangle;
	import flash.utils.ByteArray;
	
	import core.events.ServiceEvent;
	import core.model.ImportModel;
	import core.model.vo.ExportVO;
	import core.model.vo.ImportVO;
	import core.suppotClass._BaseService;
	import core.utils.BitmapDataUtil;
	import core.utils.GlobalConstValues;
	import core.utils.PNGEncoder;
	import core.utils.xmlToObject;
	
	import dragonBones.objects.DataParser;
	import dragonBones.utils.ConstValues;
	
	import light.managers.ErrorManager;
	
	import zero.zip.Zip;
	
	public final class ImportDataToExportDataService extends _BaseService
	{
		public static const IMPORT_TO_EXPORT_ERROR:String = "IMPORT_TO_EXPORT_ERROR";
		public static const IMPORT_TO_EXPORT_COMPLETE:String = "IMPORT_TO_EXPORT_COMPLETE";
		
		[Inject (name='exportModel')]
		public var importModel:ImportModel;
		
		private var _exportVO:ExportVO;
		
		public function ImportDataToExportDataService()
		{
			
		}
		
		public function changeTo(importVO:ImportVO, exportVO:ExportVO):void
		{
			importModel.vo = importVO.clone();
			_exportVO = exportVO;
			
			//更新skeleton,textureAtalsConfig的name
			importModel.name = _exportVO.name || importModel.name;
			_exportVO.name = importModel.name;
			
			// only skeleton
			if(importModel.vo.skeleton && !importModel.vo.textureAtlasConfig)
			{
				var retult:ByteArray = new ByteArray();
				retult.writeObject(importModel.vo.skeleton);
				
				_exportVO.name += "." + GlobalConstValues.XML_SUFFIX;
				
				exportSave(retult);
				return;
			}
			
			if(_exportVO.textureAtlasType == GlobalConstValues.TEXTURE_ATLAS_TYPE_SWF)
			{
				//swf格式的动画数据缩放没有意义
				_exportVO.scale = 1;
			}
			else if(_exportVO.scale != 1)
			{
				scaleData(_exportVO.scale);
			}
			
			
			if(_exportVO.configType == GlobalConstValues.CONFIG_TYPE_MERGED)
			{
				if (changeToMergedData())
				{
					return;
				}
			}
			else if (_exportVO.textureAtlasType == GlobalConstValues.TEXTURE_ATLAS_TYPE_PNGS)
			{
				if (changeToSubTextureData())
				{
					return;
				}
			}
			else
			{
				if (changeToTextureAtlasData())
				{
					return;
				}
			}
			
			light.managers.ErrorManager.getInstance().dispatchErrorEvent(this, IMPORT_TO_EXPORT_ERROR);
		}
		
		private function scaleData(scale:Number):void
		{
			var subBitmapDataMap:Object;
			var movieClip:MovieClip = importModel.vo.textureAtlasSWF as MovieClip;
			if(movieClip && movieClip.totalFrames >= 3)
			{
				//第一帧是textureAtlas，最后一帧是空，如果大于等于3帧，说明有至少一个贴图，否则可能是shape贴图
				subBitmapDataMap = {};
				var helpMatrix:Matrix = new Matrix();
				for each (var displayXML:XML in importModel.getSubTextureList())
				{
					var displayName:String = displayXML.@[ConstValues.A_NAME];
					movieClip.gotoAndStop(movieClip.totalFrames);
					movieClip.gotoAndStop(displayName);
					var subDisplay:DisplayObject = movieClip.getChildAt(0);
					
					if(scale < 1)
					{
						var rectOffSet:Rectangle = subDisplay.getBounds(subDisplay);
						helpMatrix.tx = -rectOffSet.x;
						helpMatrix.ty = -rectOffSet.y;
						
						var subBitmapData:BitmapData = new BitmapData(subDisplay.width, subDisplay.height, true, 0xFF00FF);
						subBitmapData.draw(subDisplay, helpMatrix);
						subBitmapDataMap[displayName] = subBitmapData;
					}
					else
					{
						subBitmapDataMap[displayName] = subDisplay;
					}
				}
			}
			else
			{
				subBitmapDataMap = 
					BitmapDataUtil.getSubBitmapDataDic(
						importModel.vo.textureAtlas,
						importModel.getSubTextureRectMap()
					);
			}
			
			importModel.scaleData(scale);
			
			importModel.vo.textureAtlas = 
				BitmapDataUtil.getMergeBitmapData(
					subBitmapDataMap,
					importModel.getSubTextureRectMap(),
					importModel.textureAtlasWidth,
					importModel.textureAtlasHeight,
					scale
				);
		}
		
		private function changeToMergedData():Boolean
		{
			var textureAtlasBytes:ByteArray;
			if (
				_exportVO.textureAtlasType == GlobalConstValues.TEXTURE_ATLAS_TYPE_SWF &&
				importModel.vo.textureAtlasType == GlobalConstValues.TEXTURE_ATLAS_TYPE_SWF
			)
			{
				_exportVO.name += "." + GlobalConstValues.DBSWF_SUFFIX;
				textureAtlasBytes = importModel.vo.textureAtlasBytes;
			}
			else
			{
				_exportVO.name += "." + GlobalConstValues.PNG_SUFFIX;
				textureAtlasBytes = getPNGBytes();
			}
			exportSave(
				DataParser.compressData(
					xmlToObject(importModel.vo.skeleton, GlobalConstValues.XML_LIST_NAMES), 
					xmlToObject(importModel.vo.textureAtlasConfig, GlobalConstValues.XML_LIST_NAMES), 
					textureAtlasBytes
				)
			);
			return true;
		}
		
		private function changeToTextureAtlasData():Boolean
		{
			var textureAtlasBytes:ByteArray;
			var zip:Zip = new Zip();
			var date:Date = new Date();
			
			// update texture atlas and it's name
			_exportVO.textureAtlasFileName = _exportVO.textureAtlasFileName || GlobalConstValues.TEXTURE_ATLAS_DATA_NAME;
			if (
				_exportVO.textureAtlasType == GlobalConstValues.TEXTURE_ATLAS_TYPE_SWF &&
				importModel.vo.textureAtlasType == GlobalConstValues.TEXTURE_ATLAS_TYPE_SWF
			)
			{
				_exportVO.textureAtlasFileName += "." + GlobalConstValues.SWF_SUFFIX;
				textureAtlasBytes = importModel.vo.textureAtlasBytes;
			}
			else
			{
				_exportVO.textureAtlasFileName += "." + GlobalConstValues.PNG_SUFFIX;
				textureAtlasBytes = getPNGBytes();
			}
			
			// add texture atlas to zip
			zip.add(
				textureAtlasBytes, 
				_exportVO.textureAtlasFileName,
				date
			);
			
			// update texture atlas path
			importModel.textureAtlasPath = (_exportVO.textureAtlasPath || "") + _exportVO.textureAtlasFileName;
			
			// update skeleton and texture atlas config file name and add them to zip
			_exportVO.dragonBonesFileName = _exportVO.dragonBonesFileName || GlobalConstValues.DRAGON_BONES_DATA_NAME;
			_exportVO.textureAtlasConfigFileName = _exportVO.textureAtlasConfigFileName || GlobalConstValues.TEXTURE_ATLAS_DATA_NAME;
			switch (_exportVO.configType)
			{
				case GlobalConstValues.CONFIG_TYPE_XML:
					zip.add(
						importModel.vo.skeleton.toXMLString(),
						_exportVO.dragonBonesFileName + "." + GlobalConstValues.XML_SUFFIX, 
						date
					);
					zip.add(
						importModel.vo.textureAtlasConfig.toXMLString(),
						_exportVO.textureAtlasConfigFileName + "." + GlobalConstValues.XML_SUFFIX, 
						date
					);
					break;
				
				case GlobalConstValues.CONFIG_TYPE_JSON:
					zip.add(
						com.adobe.serialization.json.JSON.encode(xmlToObject(importModel.vo.skeleton, GlobalConstValues.XML_LIST_NAMES)), 
						_exportVO.dragonBonesFileName + "." + GlobalConstValues.JSON_SUFFIX, 
						date
					);
					zip.add(
						com.adobe.serialization.json.JSON.encode(xmlToObject(importModel.vo.textureAtlasConfig, GlobalConstValues.XML_LIST_NAMES)), 
						_exportVO.textureAtlasConfigFileName + "." + GlobalConstValues.JSON_SUFFIX, 
						date
					);
					break;
				
				case GlobalConstValues.CONFIG_TYPE_AMF3:
					var bytes:ByteArray = new ByteArray();
					bytes.writeObject(xmlToObject(importModel.vo.skeleton, GlobalConstValues.XML_LIST_NAMES));
					bytes.compress();
					zip.add(
						bytes, 
						_exportVO.dragonBonesFileName + "." + GlobalConstValues.AMF3_SUFFIX, 
						date
					);
					
					bytes = new ByteArray();
					bytes.writeObject(xmlToObject(importModel.vo.textureAtlasConfig, GlobalConstValues.XML_LIST_NAMES));
					bytes.compress();
					zip.add(
						bytes, 
						_exportVO.textureAtlasConfigFileName + "." + GlobalConstValues.AMF3_SUFFIX, 
						date
					);
					break;
			}
			
			_exportVO.name += "." + GlobalConstValues.ZIP_SUFFIX;
			exportSave(zip.encode());
			zip.clear();
			return true;
		}
		
		private function changeToSubTextureData():Boolean
		{
			/*
			_xmlDataProxy.changePath();
			*/
			var zip:Zip = new Zip();
			var date:Date = new Date();
			
			var subBitmapDataMap:Object = BitmapDataUtil.getSubBitmapDataDic(
				importModel.vo.textureAtlas, 
				importModel.getSubTextureRectMap()
			);
			
			// update texture folder name and add subtextures to zip
			_exportVO.subTextureFolderName = _exportVO.subTextureFolderName || GlobalConstValues.TEXTURE_ATLAS_DATA_NAME;
			for (var subTextureName:String in subBitmapDataMap)
			{
				var subBitmapData:BitmapData = subBitmapDataMap[subTextureName];
				zip.add(
					PNGEncoder.encode(subBitmapData), 
					_exportVO.subTextureFolderName + "/" + subTextureName + "." + GlobalConstValues.PNG_SUFFIX, 
					date
				);
				subBitmapData.dispose();
			}
			
			// update skeleton file name and add it to zip
			_exportVO.dragonBonesFileName = _exportVO.dragonBonesFileName || GlobalConstValues.DRAGON_BONES_DATA_NAME;
			switch (_exportVO.configType)
			{
				case GlobalConstValues.CONFIG_TYPE_XML:
					zip.add(
						importModel.vo.skeleton.toXMLString(),
						_exportVO.dragonBonesFileName + "." + GlobalConstValues.XML_SUFFIX, 
						date
					);
					break;
				
				case GlobalConstValues.CONFIG_TYPE_JSON:
					zip.add(
						com.adobe.serialization.json.JSON.encode(xmlToObject(importModel.vo.skeleton, GlobalConstValues.XML_LIST_NAMES)), 
						_exportVO.dragonBonesFileName + "." + GlobalConstValues.JSON_SUFFIX, 
						date
					);
					break;
				
				case GlobalConstValues.CONFIG_TYPE_AMF3:
					var bytes:ByteArray = new ByteArray();
					bytes.writeObject(xmlToObject(importModel.vo.skeleton, GlobalConstValues.XML_LIST_NAMES));
					bytes.compress();
					zip.add(
						bytes, 
						_exportVO.dragonBonesFileName + "." + GlobalConstValues.AMF3_SUFFIX, 
						date
					);
					break;
			}
			
			_exportVO.name += "." + GlobalConstValues.ZIP_SUFFIX;
			exportSave(zip.encode());
			zip.clear();
			return true;
		}
		
		private function getPNGBytes():ByteArray
		{
			if(_exportVO.enableBackgroundColor)
			{
				var bitmapData:BitmapData = new BitmapData(importModel.vo.textureAtlas.width, importModel.vo.textureAtlas.height, false, _exportVO.backgroundColor);
				bitmapData.draw(importModel.vo.textureAtlas);
				
				var byteArray:ByteArray = PNGEncoder.encode(bitmapData);
				bitmapData.dispose();
				return byteArray;
			}
			
			return PNGEncoder.encode(importModel.vo.textureAtlas);
		}
		
		private function exportSave(fileData:ByteArray):void
		{
			//缩放后的bitmapData需要dispose
			this.dispatchEvent(new ServiceEvent(IMPORT_TO_EXPORT_COMPLETE, [fileData, _exportVO, importModel.vo]));
		}
	}
}