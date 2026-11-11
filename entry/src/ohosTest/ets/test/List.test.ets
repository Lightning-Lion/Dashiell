import jsonSchemaExpansionTest from '../../../test/JsonSchemaExpansion.test';
import abogusTest from '../../../test/ABogus.test';
import articleParserTest from '../../../test/ArticleParser.test';
import storageBindArgsTest from '../../../test/StorageBindArgs.test';
import storageOrderingTest from '../../../test/StorageOrdering.test';

export default function testsuite() {
  jsonSchemaExpansionTest();
  abogusTest();
  articleParserTest();
  storageBindArgsTest();
  storageOrderingTest();
}
