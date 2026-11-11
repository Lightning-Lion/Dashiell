import jsonSchemaExpansionTest from './JsonSchemaExpansion.test';
import abogusTest from './ABogus.test';
import articleParserTest from './ArticleParser.test';
import zhihuProgressiveTest from './ZhihuProgressive.test';

export default function testsuite() {
  jsonSchemaExpansionTest();
  abogusTest();
  articleParserTest();
  zhihuProgressiveTest();
}
